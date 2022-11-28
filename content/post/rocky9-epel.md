---
title: "RockyLinux9でEPELリポジトリを有効化する" # Title of the blog post.
date: 2022-11-28T21:20:35+09:00 # Date of post creation.
usePageBundles: false # Set to true to group assets like images in the same folder as this post.
featureImage: "/images/rocky.png" # Sets featured image on blog post.
thumbnail: "/images/rocky.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - 備忘録
tags:
  - RockyLinux
# comment: false # Disable comment if false.
---

CentOS系のOSではおなじみのEPELリポジトリをRockyLinux9で有効化してみる。
基本的な手順はCentOS8以前と同じだが、一部気をつけるべき点も存在する。

なお、今回用いた環境は以下。

- OS: RockyLinux9.1
- Arch: x86_64

# OSのアップデート

RockyLinux9は基本的にRHEL9準拠なので、`yum`の代わりに`dnf`が標準となっている。
といっても、基本的なコマンド体系は`yum`に非常に近いので迷うことは少ないだろう。

EPELを入れるのに先立って、以下のコマンドでシステムの全パッケージをアップグレードしておく。

```sh
$ sudo dnf upgrade
```


{{% notice note "dnf updateとdnf upgradeの違い" %}}
自分は今までCentOS系でパッケージを更新するときには`yum update`を使っていたのだが、ドキュメントには`upgrade`が記載されていたため今回はこちらを用いた。
調べてみたところ、`dnf update`は`dnf upgrade`の完全なエイリアスであり機能に違いはないらしい。
(yumの場合、`yum upgrade`は`yum --obsoletes update`の意味だったため違いがあった)
また、dnfの場合は`upgrade`が推奨されているそうだ。

参考: [Update and Upgrade Commands are the Same - Changes in DNF CLI compared to YUM](https://dnf.readthedocs.io/en/latest/cli_vs_yum.html#update-and-upgrade-commands-are-the-same)
{{% /notice %}}

# CRBの有効化

今までになかった手順なのだが、EPELリポジトリを使用する際はCodeReady Linux Builder(CRB)リポジトリの有効化が推奨されている。
CRBリポジトリとは簡単に言うと「〇〇-devel」系のビルド用のパッケージが含まれるリポジトリであり、
EPELに含まれるパッケージの中にはCRBに依存しているものが結構あるので、有効化しておいたほうがいいということらしい。

CRBは以下のコマンドにより有効化できる。

```sh
$ sudo dnf config-manager --set-enabled crb
```


# EPELの有効化

いよいよEPELリポジトリを有効化する。例によってfedoraprojectのrpmファイルを直接インストールする。

```sh
$ sudo dnf install \
    https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
    https://dl.fedoraproject.org/pub/epel/epel-next-release-latest-9.noarch.rpm
```

あとはプロンプトに従ってインストールを続行すれば完了である。

# EPEL9で提供されるパッケージについて

CentOS7時代だと、標準リポジトリは割と必需品的なパッケージでも入っていないことがよくあったし、
入っていてもバージョンが著しく古いみたいなことが多く、
それを補う存在としてEPELは実質的に必需品のような存在であった。
ところが、RHEL9になって標準リポジトリも随分時代に追いついてきたというか、
ラインナップが現代的になった上に内容も充実しているように感じる。

例えば、`nodejs`、`nginx`、`docker-compose`などはCentOS7だとEPELからしかインストールできなかったのだが、
RHEL9系だと(`docker-compose`は`podman-docker`に置き換えられたとはいえ)すべて公式リポジトリから入手することができる。
当然、`certbot`や`fail2ban`など依然としてEPELから入手する必要のあるものも存在するが、
EPELを入れないと使い物にならないという時代は終わりを迎えつつあるのかもしれない。

