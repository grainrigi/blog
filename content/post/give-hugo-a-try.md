---
title: "Hugo + Clarityでブログを作ってみる"
date: 2022-11-12T19:10:40+09:00
categories:
  - 備忘録
tags:
  - hugo
---

今までブログを書くのにはてなブログを利用していたが、
せっかく独自ドメインをとったし何か自前のブログを持ってみたいと思った。

WordPressはDB必須でデプロイが面倒そうだったので、
静的サイトジェネレータでは割と有名なHugoを使ってみる。

# 準備

## hugoコマンドのインストール

Hugoは`hugo`という単一のコマンドを使って記事の追加・ビルド等を行う。
よってまずは`hugo`コマンドをインストールする必要がある。

参考: [Quick Start | Hugo](https://gohugo.io/getting-started/quick-start/)

ArchLinuxの場合、hugoは公式リポジトリに存在する。

```sh
sudo pacman -S hugo
```

## サイトの作成

```sh
hugo new site myblog
```

これで`myblog`ディレクトリに必要なファイルが準備される。

# Clarityのセットアップ

この後、Quick Startガイドに従うと、gitのsubmoduleとしてテーマをインストールするのだが、
テーマによっては全く別のインストール方法を用いる必要がある場合がある。

今回用いる「Clarity」というテーマは、Hugo modules(go moduleを活用した方式)を使ってのインストールが推奨されている。

参考: [Getting up and running | chipzoller/hugo-clarity](https://github.com/chipzoller/hugo-clarity#getting-up-and-running)

## goのインストール

Hugo modules(`hugo mod`)を用いる場合、golangのインストールが必須となる。

```sh
sudo pacman -S go
```

## 設定ファイル・雛形の取込み

Clarityでは`exampleSite`の設定の取込みが必須となっている。
(最初、設定を取り込まずにセットアップしてしまったのだが、Code Blockの表示に不具合が生じた。)

```sh
cd myblog
hugo mod init myblog
wget -O - https://github.com/chipzoller/hugo-clarity/archive/master.tar.gz | tar xz && cp -a hugo-clarity-master/exampleSite/* . && rm -rf hugo-clarity-master && rm -f config.toml
```

なお、これにより、`config.toml`が`config/_default`以下に移動するので注意。

## テーマのインポート

themeの参照先をローカルでなくGithubに設定する。

`config/_default/config.toml`で以下のように設定。

```toml
# theme = 'hugo-clarity'
theme = ["github.com/chipzoller/hugo-clarity"]
```

## その他設定の変更

### config.toml

baseurl, copyright, 言語を変更する。

```toml:config.toml
# set `baseurl` to your root domain
# if you set it to "/" share icons won't work properly on production
baseurl = "https://blog.grainrigi.net/"  # Include trailing slash
# title = "Clarity"  # Edit directly from config/_default/languages.toml # alternatively, uncomment this and remove `title` entry from the aforemention file.
copyright = "Copyright © 2022, grainrigi; all rights reserved."

# (中略)

DefaultContentLanguage = "ja"

# (略)
```

### language.toml

en -> jaに変更、ptを削除

```
[ja]
  title = "Arch使いの日記"
  languagename = "japanese"
  weight = 1
```

### menus

menu_en.tomlをmenu_ja.tomlに移動する。
menu_pt.tomlは削除。

### ロゴ

`static/logos/logo.png`を置き換えるか、削除する。
削除した場合は、titleに設定した文字列が代わりに表示される。
(ただ、これはimgのaltが表示されているだけなので何かしらタイトル画像を作成することを推奨)


# 記事の作成

準備が終わったので記事を作ってみる。
まずは`hugo new`コマンドで空の記事を作成する。

※ Clarityの場合、`posts`ではなく`post`を使用する。

```
hugo new post/my-first-post.md
```

すると、以下のようなファイルが作成される。

```
---
title: "My First Post"
date: 2022-11-12T19:19:11+09:00
draft: true
---

```

`---`で囲まれた部分はメタデータなので、その下にMarkdownで記事を記述すれば良い。

{{% notice note "Note" %}}
メタデータを`---`で囲むと内容はyamlとして解釈され、`+++`で囲むとtomlとして解釈される。
{{% /notice %}}

## 作成した記事のプレビュー (Hugo Server)

`hugo server`をコマンドを使うことで、ローカル環境でサイトを見ることができる。

```
hugo server -D
```

`-D`をつけると`draft: true`の記事も一覧に表示されるようになる。
逆に、`draft: true`の記事はproduction buildだと一覧には表示されない。


## その他のメタデータ(タグ、カテゴリ等)

Clarityは記事にタグやカテゴリをつける機能がある。

```
---
title: "My First Post"
date: 2022-11-12T19:19:11+09:00
categories:
  - 備忘録
tags:
  - hugo
---
```

## カスタムCSS

`assets/sass/_custom.sass`にカスタムCSSを書くことが可能。

コードブロックの直後に見出しをおいた場合に隙間が狭く感じたので今回はそれを修正してみる。

以下のようにオフサイドルールを用いたsassを記述する。

```css
.highlight_wrap
  &+h1, &+h2, &+h3, &+h4, &+h5
    margin-top: 30px
```

# デプロイ

`hugo`コマンドを実行すると静的ファイルが生成される。

```sh
$ hugo
Start building sites … 
hugo v0.105.0+extended linux/amd64 BuildDate=unknown

                   | JA  
-------------------+-----
  Pages            | 25  
  Paginator pages  |  0  
  Non-page files   |  0  
  Static files     | 62  
  Processed images |  0  
  Aliases          | 17  
  Sitemaps         |  1  
  Cleaned          |  0  
```

あとは`./public/`以下のファイルを適切に公開すればデプロイ完了となる。


# まとめ

今回はHugoを使ってブログを作成してみた。

Hugo用のテーマはブログテーマであってもシンプルで機能の少ないものが多いのだが、
Clarityはタグやカテゴリ等の機能が充実しているのでブログを作るのにはかなり便利に感じた。
