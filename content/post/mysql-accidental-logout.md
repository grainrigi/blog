---
title: "【MySQL/MariaDB】突然のAccess denied for userエラーにはVIEWのDEFINERを疑え" # Title of the blog post.
date: 2022-11-20T22:08:47+09:00 # Date of post creation.
usePageBundles: false # Set to true to group assets like images in the same folder as this post.
featureImage: "/images/mariadb.png" # Sets featured image on blog post.
thumbnail: "/images/mariadb.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - 技術記事
tags:
  - MySQL
  - MariaDB
# comment: false # Disable comment if false.
---

MariaDBでユーザーアカウントの整理をしている際、突然以下のような権限エラーが発生するようになってしまった。

```
ERROR 1045 (28000): Access denied for user 'user'@'%' (using password: YES)
(userは削除したのとは全く別の存在するユーザー)
```

ちなみにこのエラーが発生したのは最初の接続時ではなく**クエリの実行直後である**。
そもそもこのエラーが最初の認証以外で起こること自体おかしい気がするが、
さらに言えばこのユーザーはちゃんと存在しているし、使用しているパスワードも完全に正しいのである。

ちなみにこのエラーを引き起こしていたクエリは普通のSELECT文だったのだが、
他のクエリと違って**ビューに対するSELECTを発行していた。**
調査したところ、どうもユーザーの削除によりビューの設定の整合性が失われ、
呼び出しているビューのセキュリティ機能で弾かれてしまっているらしい。

# MySQLビューのセキュリティ

そもそも、MySQLのビューがSELECT文で呼び出された場合、
結果セットを作るためにさらに内部でもう一度SELECT文を呼び出すわけだが、
**内部でSELECT文を実行する際の権限は、必ずしも現在のユーザーの権限が用いられるわけではない。**

具体的には、`CREATE VIEW`で指定できる`DEFINER`と`SQL SECURITY`というパラメーターによって定まる。

- `SQL SECURITY`
  - ビューのSELECT文を実行するユーザーの決定方法を指定する。`DEFINER`または`INVOKER`を指定できる
  - `SQL SECURITY = DEFINER`の場合、`DEFINER = [user]`で指定されたユーザーの権限を用いる
  - `SQL SECURITY = INVOKER`の場合、ビューを呼び出したユーザーの権限を用いる
- `DEFINER`
  - `SQL_SECURITY = DEFINER`のときに参照されるユーザー

このように、ビューを呼び出す際には、現在のユーザーの権限だけでなく`DEFINER`のユーザーの権限も参照する可能性があるのである。

## DEFINERとユーザー削除

`CREATE VIEW`でビューを作る際に上記のパラメータを指定することはまず無いと思うが、
この場合、`CREATE VIEW`を呼び出したユーザーが`DEFINER`となり、`SQL SECURITY`も`DEFINER`にセットされる。

では、この`CREATE VIEW`を呼び出したユーザーを後から削除した場合どうなるかというと、
ビューの`DEFINER`は自動で書き換わることはないため、
`DEFINER`は存在しないユーザーを参照することになる。
これにより、ビューを呼び出した際、
**存在しないユーザーの権限を参照しようとするため、ERROR 1045 Access deniedが発生してしまうのである。**

このようにして先述の現象が起こるというわけである。
(一つ納得がいかないのが、あたかも現在のユーザーのログイン権限が無いように表示されてしまうことであるが、
これ自体は仕様としか言いようがないのだろう。)

# 解決策

`DEFINER`に指定されたユーザーが存在しないのが問題なので、`ALTER TABLE`ステートメントによりビューを再定義する。

```
# はじめにビューの定義を持ってくる必要がある
> SHOW CREATE VIEW my_view;
+---------+----------------------
| View    | Create View 
+---------+---------------------
| my_view | CREATE ALGORITHM=UNDEFINED DEFINER=`originaldefiner`@`%` SQL SECURITY DEFINER VIEW `my_view` AS select ...
# ↑のselect文をコピーして用いる
> ALTER VIEW `my_view` AS select ...
```

これにより、`DEFINER`が現在のユーザー(存在するユーザー)に置き換わるため、問題が解決するはずである。
なお、`ALTER VIEW`を実行する際には`CREATE VIEW`, `DROP`およびビューの参照先テーブルの`SELECT`権限が必要となるので注意。

# 参考文献

[MySQL :: MySQL 8.0 Reference Manual :: 13.1.23 CREATE VIEW Statement](https://dev.mysql.com/doc/refman/8.0/en/create-view.html)

[MySQLでViewを使うときに注意すること - よかろうもん！](https://interu.hatenablog.com/entry/20090210/1234192800)
