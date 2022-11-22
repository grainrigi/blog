---
title: "Misskeyを32bit環境(Debian i386)で動かしてみる" # Title of the blog post.
date: 2022-11-22T19:47:21+09:00 # Date of post creation.
categories:
  - 備忘録
tags:
  - Misskey
# comment: false # Disable comment if false.
---

昨今のTwitterに関する騒動の影響で、「ポストTwitter」になりうるプラットフォームが俄に注目を集めているらしい。
その一つがセルフホスト型のプラットフォームの[Misskey](https://misskey-hub.net/)であり、Twitterを踏襲したタイムラインをサポートしつつ、
Slackライクなリアクションを投稿につけることが出来たり、UIの高度なカスタマイズが出来たりするなどいくつかのユニークな特徴を有している。
また、ActivityPubによる他インスタンスとの連携に対応しており、
他のMisskeyインスタンスだけでなく、Mastodon等とも連携可能な非中央集権型のプラットフォームとなっている。

MisskeyはNode.jsで書かれているため、本来はLinux x86環境で動かすことはできないのだが、
Node.jsの非公式ビルドを用いる等、様々な工夫をすることで32bit環境でも動かすことが出来た。
今回はその記録として構築手順を書いていこうと思う。

# 概要

今回用いる環境はDebian 11.5 (bullseye) i386である。(ArchLinuxは公式にはx86_64しか対応していない為。)
また、検証に際してはVirtualBox上のVMにて作業を行っている。

Misskeyの構築手順としてDockerを使ったインストールが推奨されているため、今回はこれに従う。

[Dockerを使ったMisskey構築 | Misskey Hub](https://misskey-hub.net/docs/install/docker.html)

## やる必要のあること

32bit環境で動かすにあたって、以下の障壁をクリアする必要がある。

- i386用のNode.js Dockerイメージの準備
- prebuiltバイナリを用いるパッケージへの対処
  - `@tensorflow/tfjs-node`を使わないようにする
  - `sharp`の依存ライブラリの手動ビルド

以下ではこれらの解決方法を解説する。

※ 構築手順のみを知りたい場合、[完全な構築手順](#完全な構築手順)を参照

## i386用のNode.js Dockerイメージの準備

Node.jsは公式でLinux x86をサポートしないため、Docker Hubの公式イメージにもlinux/386版は存在しない。
ただ、Node.jsの[非公式ビルド](https://unofficial-builds.nodejs.org/)でx86版が存在するため、
x86版Node.jsイメージを作ることは技術的には可能である。

この方法で作られたと思われる非公式のNode.jsイメージがBalena社から提供されているので、
今回はありがたくこれを使わせてもらうことにする。

[balenalib/i386-node - Docker Image | Docker Hub](https://hub.docker.com/r/balenalib/i386-node)

Misskeyの公式で使われている16.15.1-bullseyeもバッチリ存在している。
(ただし、slim版は無い模様)

## `@tensorflow/tfjs-node`を使わないようにする

Misskeyはオプション機能としてNSFW画像の自動判定機能が存在し、Tensorflowを用いて実装されている。
TensorflowのNode.js用ライブラリである`@tensorflow/tfjs-node`はネイティブのlibtensorflowに依存しているのだが、
このlibtensorflowはx86をサポートしていない。
このため、今回はNSFW機能の利用を諦めて`@tensorflow/tfjs-node`のインストールを回避するようにする。

なお、Misskey自体は既に`@tensorflow/tfjs-node`をoptionalDependenciesに移動しているため、
本来はパッケージのインストール時に`--ignore-optional`を指定するのみで済む筈なのだが、
実際の`nsfwjs`のpeerDependenciesを正しく扱っていないためこのままだと依存関係エラーで起動しなくなってしまう。

`nsfwjs`のpeerDependenciesに含まれているのは`@tensorflow/tfjs`であり、
これ自体はlibtensorflowに依存していないため、単純に`dependencies`に追加すれば解決する。

## `sharp`の依存ライブラリの手動ビルド

`sharp`はNode.js用の画像処理パッケージで、Misskeyではアップロードされた画像のリサイズ等に用いていると思われる。
このパッケージはネイティブのライブラリであるlibvipsに依存しており、
通常のインストールであればprebuiltバイナリが自動でダウンロード展開されるようになっているのだが、
x86の場合は手動でビルドした上でホスト上に直接インストールする必要がある。
(ビルド手順: [Building libvips from source](https://www.libvips.org/install.html#building-libvips-from-source))

なお、Debianのリポジトリにも[libvips42](https://packages.debian.org/bullseye/libvips42)というパッケージが存在するのだが、
こちらはバージョンが古く(これは8.10.5だが、sharpには8.11以降が必要)、
`sharp`のインストール時に必要なcmake関係のファイルも不足しているため、これを用いることは出来ない。

今回は、Docker上でlibvipsをビルドし、`ninja install`で直接インストールして使ってしまうことにした。
この際、libvipsの依存ライブラリを色々とインストールする必要があるのだが、
これに関してはDebian公式のlibvips-devおよびlibvips42の依存パッケージを参考にすることとする。


# 完全な構築手順

以下では、Misskey Hubで説明されていることも含めて一通りの構築手順を説明する。

## パッケージの更新

まず、サーバーのパッケージをすべて最新にしておく(念の為)。

```sh
$ sudo apt -y udpate
$ sudo apt -y upgrade
$ reboot
```

## 必要なツールの準備

Git, Docker等のツールが必要になるのでインストールする。

```
$ sudo apt -y install git docker.io docker-compose
```

## Misskeyのクローン

Misskeyは常にソースからビルドする必要がある。
このため、まずはGitHubからソースコードをクローンする。

```sh
$ git clone -b master https://github.com/misskey-dev/misskey.git
$ cd misskey
```

## 設定

`.config`内に設定ファイルを作る必要があるため、まずはサンプルファイルをコピーする。

```sh
$ cp .config/example.yml .config/default.yml
$ cp .config/docker_example.env .config/docker.env
```

次に、`.config/default.yml`を以下のように編集する。

- `url`を`http://localhost:3000/`に変更
- `db`の`host`を`db`に変更
- `redis`の`host`を`redis`に変更

(`docker.env`にはDBのパスワードしか書いていないので、今回はとりあえずそのままで良い)

## Dockerfileの編集

次に、イメージビルドのスクリプトファイルである`Dockerfile`を編集していく。

### 32bitのNode.jsを使う

FROMから始まる行(2箇所)を以下のように変更する。

```diff
-FROM node:16.15.1-bullseye AS builder
+FROM balenalib/i386-node:16.15.1-bullseye AS builder

ARG NODE_ENV=production

WORKDIR /misskey

COPY . ./

RUN apt-get update
-RUN apt-get install -y build-essential
+RUN apt-get install -y build-essential git

# (中略)

-FROM node:16.15.1-bullseye-slim AS runner
+# slim版はないのでbullseyeをそのまま用いる
+FROM balenalib/i386-node:16.15.1-bullseye AS runner

# (略)
```

gitを追加でインストールしているのは、balenalib版のbullseyeイメージにgitが含まれていないためである。
(本家では含まれている模様)

### libvipsをビルド・インストールする

以下のようにDockerfileを編集する。

```diff
FROM balenalib/i386-node:16.15.1-bullseye AS builder

ARG NODE_ENV=production

WORKDIR /misskey

COPY . ./

+# libvipsのバージョンは、sharpで指定されているバージョンと揃える
+# 確認先: https://github.com/lovell/sharp/blob/main/package.json#L157
+ARG VIPS_VER=8.13.3

RUN apt-get update
-RUN apt-get install -y build-essential git
+RUN apt-get install -y build-essential git python3
+RUN apt-get install -y libjpeg-dev libtiff-dev libpng-dev libgif-dev \
+ librsvg2-dev libpoppler-glib-dev gobject-introspection zlib1g-dev libfftw3-dev \
+ liblcms2-dev libmagickcore-dev libmagickwand-dev libfreetype6-dev libpango1.0-dev \
+ libfontconfig1-dev libglib2.0-dev libice-dev libimagequant-dev liborc-0.4-dev \
+ libheif-dev libmatio-dev libexpat1-dev libcfitsio-dev libopenslide-dev libwebp-dev \
+ libgsf-1-dev libgirepository1.0-dev bc meson
+RUN curl -O -L https://github.com/libvips/libvips/releases/download/v$VIPS_VER/vips-$VIPS_VER.tar.gz \
+ && tar xf vips-$VIPS_VER.tar.gz \
+ && cd vips-$VIPS_VER \
+ && meson setup build --prefix=/vips \
+ && cd build \
+ && ninja \
+ && ninja test \
+ && ninja install
+RUN cp -r /vips/. /usr/
RUN git submodule update --init
RUN yarn install
RUN yarn build
RUN rm -rf .git

FROM balenalib/i386-node:16.15.1-bullseye AS runner

WORKDIR /misskey

RUN apt-get update
RUN apt-get install -y ffmpeg tini

+RUN apt-get install -y libcairo2 libcfitsio9 libexif12 libexpat1 libfftw3-double3 \
+ libfontconfig1 libgcc-s1 libgif7 libglib2.0-0 libgsf-1-114 libheif1 libimagequant0 \
+ libjpeg62-turbo liblcms2-2 libmagickcore-6.q16-6 libmatio11 libopenexr25 \
+ libopenslide0 liborc-0.4-0 libpango-1.0-0 libpangoft2-1.0-0 libpng16-16 \
+ libpoppler-glib8 librsvg2-2 libstdc++6 libtiff5 libwebp6 libwebpdemux2 \
+ libwebpmux3 zlib1g
+
+COPY --from=builder /vips/ /usr/
COPY --from=builder /misskey/node_modules ./node_modules
COPY --from=builder /misskey/built ./built
COPY --from=builder /misskey/packages/backend/node_modules ./packages/backend/node_modules
COPY --from=builder /misskey/packages/backend/built ./packages/backend/built
COPY --from=builder /misskey/packages/client/node_modules ./packages/client/node_modules
COPY . ./

ENV NODE_ENV=production
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["npm", "run", "migrateandstart"]
```

行数が多いが、ほとんどがlibvipsの依存関係のインストールである。
libvipsのバージョンは必要に応じて変更すること。

また、今回のDockerfileは[マルチステージビルド](https://matsuand.github.io/docs.docker.jp.onthefly/develop/develop-images/multistage-build/)を利用しており、
`builder`と`runner`の2つのコンテナを用いている。
`libvips`はビルド時と実行時の両方で必要であるため、両方のコンテナにインストールする必要がある。
これを実現するため、一旦`/vips/`以下にインストールし、
`builder`と`runner`の両方で`/vips/`の内容をシステムにコピーするようにしている。
(マルチステージングビルドではファイルコピー以外でコンテナ間の連携が出来ないため)

## 依存パッケージの編集

tensorflowを依存関係から外すため、以下の作業を行う。

## `scripts/install-packages.js`の編集

tensorflowに依存しているのは`packages/backend`内のモジュールであり、
これのパッケージのインストールは`scripts/install-packages.js`で行われている。
このため、以下のようにして`yarn install`に`--ignore-optional`オプションを追加する。

```diff
const execa = require('execa');

(async () => {
  console.log('installing dependencies of packages/backend ...');

- await execa('yarn', ['--force', 'install'], {
+ await execa('yarn', ['--force', 'install', '--ignore-optional'], {
    cwd: __dirname + '/../packages/backend',
    stdout: process.stdout,
    stderr: process.stderr,
  });
```

これにより、`@tensorflow/tfjs-node`がインストールされなくなる。

## `packages/backend/package.json`の編集

先述の理由により`@tensorflow/tfjs`を明示的にインストールする必要があるため、
以下のように`packages/backend/package.json`を編集する。

```diff
{
  // (中略)
  "optionalDependencies": {
    "@tensorflow/tfjs-node": "3.20.0"
  },
  "dependencies": {
    "@bull-board/koa": "4.2.2",
    "@discordapp/twemoji": "14.0.2",
    "@elastic/elasticsearch": "7.11.0",
    "@koa/cors": "3.1.0",
    "@koa/multer": "3.0.0",
    "@koa/router": "9.0.1",
    "@peertube/http-signature": "1.7.0",
    "@sinonjs/fake-timers": "9.1.2",
    "@syuilo/aiscript": "0.11.1",
+   "@tensorflow/tfjs": "3.20.0",
    "ajv": "8.11.0",
    "archiver": "5.3.1",
    "autobind-decorator": "2.4.0",
// (略)
```

このとき、`@tensorflow/tfjs-node`と`@tensorflow/tfjs`のバージョンが一致するようにする。

## イメージのビルド

ここまでの手順が完了したら、以下のコマンドで一旦イメージをビルドする。

```sh
$ docker-compose build
```

ビルドが成功すると以下のような出力が出るはずである。

```
Successfully built ce6afa9c901c
Successfully tagged misskey_web:latest
```

もしビルドに失敗してしまった場合、変更点に誤りがないかをよく確認すること。
(特に要求されるlibvipsのバージョンは頻繁に変わる可能性があるため、きちんと書き換えられているかよく確認する。)

なお、イメージ何回かビルドし直すと不要なキャッシュが溜まっていくので、
再ビルド前に以下のコマンドでキャッシュを削除すると良い。

```
$ docker image prune
```

## サーバーの立ち上げ

ビルドに成功したら、あとはサーバーを立ち上げるだけである。

```sh
$ docker-compose up -d
```

初回起動はデータベースのマイグレーションが走るため時間がかかるが、
しばらくするとサーバーが立ち上がるので、
`http://localhost:3000/`にアクセスして正常に動作しているかどうか確認する。