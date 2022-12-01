---
title: "VSCode Dev Container内で保存したファイルのパーミッション問題に対処する" # Title of the blog post.
date: 2022-12-01T20:34:33+09:00 # Date of post creation.
usePageBundles: true # Set to true to group assets like images in the same folder as this post.
featureImage: "vscode.png" # Sets featured image on blog post.
thumbnail: "vscode.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - 技術記事
tags:
  - VSCode
# comment: false # Disable comment if false.
---

VSCode Dev Container内で保存したファイルの所有者はコンテナの実行ユーザーになってしまうため、
rootで立ち上がったコンテナを使って作業をすると、保存したファイルをホスト側から編集できなくなる(Permission Deniedとなる)という問題が生じる
(Windowsの場合は発生しない)。
この問題に対処するため、Dev Containerの実行ユーザーをホスト側と揃えるようにするための方法を見ていく。

なお、今回の基本的なアイデアはこちらのページを参考にしている。

[VSCode Dev Container on WSL2のPermission問題メモ - Qiita](https://qiita.com/noonworks/items/472008c25a20d0598505)

# 設定ファイルの編集

## devcontainer.jsonの編集

まず、devcontainer.jsonに以下の設定を追加する。

```json
{
  "initializeCommand": "${localWorkspaceFolder}/.devcontainer/getuid",
}
```

`initializeCommand`は、DevContainerの起動時に**ホスト側で**実行するスクリプトを指定するオプションである。

今回は、`getuid`(シェルスクリプト)にて現在のユーザーのUID, GID, ユーザー名を抽出するのに使用する。

## getuid, getuid.cmdの作成

まず、以下の内容で`getuid`というファイルを作成する。

```sh
#!/bin/bash
echo "UID=$(id -u $USER)" > .devcontainer/.env
echo "GID=$(id -g $USER)" >> .devcontainer/.env
echo "USERNAME_=$USER" >> .devcontainer/.env
```

さらに、一応実行権限を付与する。

```sh
$ chmod +x .devcontainer/getuid
```

Mac, Linuxの場合はこれでうまくUID, GID, ユーザー名を抽出できる。
ここで保存された`.env`は次節で示すdocker-compose.ymlで自動的に読み込まれる。

ちなみに、4行目で`USERNAME_=`(アンダースコア付)としているのは、`USERNAME`がWindowsの環境変数で既に定義されており干渉するためである。

### Windows対応

Windowsの場合はUID, GIDの概念がなく、そもそもこのパーミッション問題自体が発生しないので抽出する必要がない。
今回は、Windowsの場合にはそもそも`.env`を作成しないようにする。

以下の内容で`getuid.cmd`というファイルを作成する。

```cmd
@echo off

REM .envがあれば削除
if exist .devcontainer\.env del .devcontainer\.env
```

パス区切りが「/(スラッシュ)」ではなく「\\(バックスラッシュ)」であることに注意。

※ `initializeCommand`では`getuid`を指定しているが、同名の`.cmd`ファイルが存在するとWindowsの場合のみ自動でこちらが実行される。

## docker-compose.ymlの編集

docker-compose.ymlの`build`を以下のようにする。

```yml
version: '3'

services:
  dev:
    build:
      context: .
      args:
        USERNAME: $USERNAME_
        UID: $UID
        GID: $GID
    stdin_open: true
    # (略)
```

ポイントは、先程作成された`.env`の内容を`args`で`Dockerfile`に渡すことである。

これにより、`Dockerfile`内でホスト側のUID, GID, ユーザー名でユーザーを作成できるようになる。

## Dockerfileの編集

Dockerfileを以下のようにする。

```dockerfile
FROM golang:1.19-bullseye

# (中略)

# 以下を追加
ARG USERNAME=root
ARG UID
ARG GID

# 中でrootに昇格できるようにsudoを入れる
RUN apt -y update \
 && apt -y install sudo

# ホストと同一のUID・GID・ユーザー名でユーザー作成
RUN [ -n "$UID" ] && (groupadd --gid $GID $USERNAME \
 && useradd --uid $UID --gid $GID -m $USERNAME \
 && echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USERNAME \
 && chmod 0440 /etc/sudoers.d/$USERNAME)

USER $USERNAME

# (略)
```

ユーザー等を作成する前に`[ -n "$UID" ]`でユーザーを作成する必要があるかどうかテストしている。
(Windowsの場合はUIDの内容が空になっているため、このコマンドは失敗し後続のスクリプトはスキップされる)
また、Windowsの場合は`USERNAME`がデフォルト値の`root`になるため、
最後の`USER`コマンドで`root`が指定される。

{{% notice note "同一UIDのユーザーがコンテナ内に既に存在する場合" %}}
上記のスクリプトはコンテナ内に一般ユーザーが存在しない場合にはうまくいくが、
`node:alpine`のように一般ユーザーが既に存在する場合、
UID・GIDが衝突してしまいスクリプトが失敗する場合がある。

一般ユーザーがコンテナ内に存在する場合、以下のようにして既存ユーザーを使うようにしたほうが良い。

例: コンテナ内の`node`ユーザーを使用する

1. `getuid`でnodeユーザーを指定する
```sh
#!/bin/bash
echo "UID=$(id -u $USER)" > .devcontainer/.env
echo "GID=$(id -g $USER)" >> .devcontainer/.env
echo "USERNAME_=node" >> .devcontainer/.env
```
2. DockerfileでUID・GIDをホストと同じになるように変更
```dockerfile
FROM node:alpine

# (中略)

# 以下を追加
ARG USERNAME=root
ARG UID
ARG GID

# alpineイメージの場合、usermod等もインストールする必要あり
RUN apk add --no-cache sudo shadow

# 既存のユーザーのUID・GIDを変更
RUN [ -n "$UID" ] && (groupmod --gid $GID $USERNAME \
 && usermod --uid $UID --gid $GID $USERNAME \
 && echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USERNAME \
 && chmod 0440 /etc/sudoers.d/$USERNAME \
 && chown -R $UID:$GID /home/$USERNAME)

USER $USERNAME
```

{{% /notice %}}

# 動作確認

以上で設定ファイルの編集は完了なので、実際に`Rebuild and Reopen in Container`を実行してコンテナが一般権限で実行されるかを確認する。

なお、`initializeCommand`を指定した弊害としてコンテナ内ターミナルがデフォルトで立ち上がらなくなる。
ターミナル右上の「+」ボタンからコンテナ内ターミナルを立ち上げると、以下のように一般ユーザーで実行されるはずである。

```
a82773d0e42b:/workspace$ id
uid=1000(user) gid=1000(user) groups=1000(user)
```











