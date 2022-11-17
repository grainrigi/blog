---
title: "Elasticsearch8をDockerで使ってみる (2) | 永続化とX-Packセキュリティ" # Title of the blog post.
date: 2022-11-17T21:25:32+09:00 # Date of post creation.
toc: false # Controls if a table of contents should be generated for first-level links automatically.
featureImage: '/images/elasticsearch-docker.png'
thumbnail: '/images/elasticsearch-docker.png'
usePageBundles: false # Set to true to group assets like images in the same folder as this post.
categories:
  - 技術記事
tags:
  - Elasticsearch
  - Docker
# comment: false # Disable comment if false.
---

※この記事は前回([Elasticsearch8をDockerで使ってみる (1) | シングルノード構成](/post/elasticsearch-docker-1/))の続きとなります。

前回の記事では簡単なシングルノードクラスタを構築してみたが、
データの永続化が行われていないため`docker-compose down`を実行するとデータが失われてしまう状態となっていた。
そこで、今回はデータの永続化を有効にするところから始めてみる。

# 永続化に立ちはだかる壁

Elasticsearchのデータは`/usr/share/elasticsearch/data`に格納されるようになっている。
とりあえずこのディレクトリをVolumeに結びつけて永続化してみる。

```yml:docker-compose.yml
services:
  es:
    build:
      context: .
    environment:
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    ports:
      - 9200:9200
    volumes:
      - es_data:/usr/share/elasticsearch/data
volumes:
  es_data:
```

この状態で`docker-compose up -d`すると、以下のようなエラーで終了してしまった。

```
...
bootstrap check failure [1] of [2]: the default discovery settings are unsuitable for production use; at least one of [discovery.seed_hosts, discovery.seed_providers, cluster.initial_master_nodes] must be configured
bootstrap check failure [2] of [2]: Transport SSL must be enabled if security is enabled. Please set [xpack.security.transport.ssl.enabled] to [true] or disable security by setting [xpack.security.enabled] to [false]
ERROR: Elasticsearch did not exit normally - check the logs at /usr/share/elasticsearch/logs/docker-cluster.log
...
ERROR: [2] bootstrap checks failed. You must address the points described in the following [2] lines before starting Elasticsearch.
```

シングルノード構成のときには出てこなかったエラーがいきなり出てきてしまったが、
これはElasticsearchコンテナが本番環境用のモードで起動したためである。
(Elasticsearchのdockerイメージは、`/usr/share/elasticsearch/data`の中身がデフォルトの状態のときのみ開発用モードで動作するようである。)
本番環境用のElasticsearchコンテナでは、以下の設定を手動で行う必要がある。

- クラスタの初回起動に必要なマスターノードの指定
- X-Packセキュリティの設定(SSL証明書の発行・設定)

上記のエラーはこれらの設定に不備があることを指摘している。
一見不便に思えるが、一般的なElasticsearchの本番構成だと複数のノードを組み合わせるのが一般的なので、
むしろ当然の動作と言える。

ということで、上記の設定を簡単に行っていくこととする。

# クラスタのマスターノードの指定

クラスタを初回起動する際に、最低限以下の設定を入れる必要がある。

- `cluster.initial_master_nodes`: 最初にマスターノードとして動作するノード
- `discovery.seed_hosts`: マスターノードのアドレス

今回はシングルノードで構成するので、とりあえず両方とも自分自身を指定すれば良い。
(詳細についてはマルチノード構成を扱う際に取り上げようと思う。)

これらの設定は環境変数に設定する。

```yml:docker-compose.yml
    environment:
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - "cluster.initial_master_nodes=es"
      - "discovery.seed_hosts=es"
```

`es`はdocker-compose内のサービス名を指定しており、これはdocker networkのalias機能によりコンテナのIPアドレスに解決される。

# X-Packセキュリティのセットアップ

X-PackはElasticsearchで標準的に使用されているセキュリティプラグインである。
Elasticsearch7.xまではオプショナルのプラグインだったが、
8.0以降は標準で有効になっているため改めてインストールする必要はない。

X-Packセキュリティを使うにあたって、以下の準備を行う必要がある。

- CA証明書の発行
- 各ノードの証明書の発行
- 各ノードへの証明書の設定

## CA証明書の発行

以降、ホスト側の`certs`ディレクトリに証明書関連のファイルを格納することとする。

証明書に関する各種操作は`elasticsearch-certutil`コマンドで簡単に行うことができる。
まずは以下のコマンドを実行してCA証明書を発行する。

```sh
$ mkdir -p certs
$ docker run --rm -it -v "$PWD/certs:/certs" elasticsearch:8.5.0 \
  bin/elasticsearch-certutil ca --silent --pem -out /certs/ca.zip
$ unzip certs/ca.zip -d certs
```

`certs/ca/ca.crt`にCA証明書が発行される。
また、`certs/ca/ca.key`はCA証明書の秘密鍵なので、セキュリティを考慮するのであれば安全性の高い場所に移動して保管するのが望ましい。
(今回は検証用なのでここに置いたままにしておく)

## 各ノードの証明書の発行

先程発行したCAを用いて、各ノードの証明書を発行する。

まずは`certs/instances.yml`に以下のようにノードリストを記述する。

```yml:certs/instances.yml
instances:
  - name: es
    dns:
      - es
      - localhost
    ip:
      - 127.0.0.1
```

`dns`と`ip`で指定しているのは、証明書に記載されるCommon Nameである。
HTTPSでアクセスした際、ここで指定したCommon NameとリクエストURLのホスト名が一致する必要がある。
今回は本来のホスト名である`es`の他に`localhost`と`127.0.0.1`を指定しているが、
これらはdockerのポートバインディングを経由して`https://localhost:9200`のようにアクセスする際に必要となる。

ノードリストを作成したら以下のコマンドを実行して証明書を発行する。

```sh
$ docker run --rm -it -v "$PWD/certs:/certs" elasticsearch:8.5.0 \
  bin/elasticsearch-certutil cert --silent --pem \
  -out /certs/certs.zip --in /certs/instances.yml \
  --ca-cert /certs/ca/ca.crt --ca-key /certs/ca/ca.key
$ unzip certs/certs.zip -d certs
```

これにより、`certs/es`以下に`es.crt`(証明書)と`es.key`(秘密鍵)が作成される。

## 各ノードへの証明書の設定・TLSの有効化

最後に、Elasticsearchノードが今回発行した証明書を使用するように設定する。
docker-composeを以下のように編集する。

```
services:
  es:
    build:
      context: .
    environment:
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
      - cluster.initial_master_nodes=es
      - discovery.seed_hosts=es
      - ELASTIC_PASSWORD=p@ssw0rd
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=true
      - xpack.security.http.ssl.key=certs/es/es.key
      - xpack.security.http.ssl.certificate=certs/es/es.crt
      - xpack.security.http.ssl.certificate_authorities=certs/ca/ca.crt
      - xpack.security.http.ssl.verification_mode=certificate
      - xpack.security.transport.ssl.enabled=true
      - xpack.security.transport.ssl.key=certs/es/es.key
      - xpack.security.transport.ssl.certificate=certs/es/es.crt
      - xpack.security.transport.ssl.certificate_authorities=certs/ca/ca.crt
      - xpack.security.transport.ssl.verification_mode=certificate
    ports:
      - 9200:9200
    volumes:
      - ./certs:/usr/share/elasticsearch/config/certs:ro
      - es_data:/usr/share/elasticsearch/data
volumes:
  es_data:
```

`xpack.security.http`と`xpack.security.transport`の2種類があるが、2つとも設定している内容は全く同一である。
これは、以下の2種類の通信それぞれに暗号化を設定していることになる。

- `http`: クライアントとノードの通信、HTTPSにより保護
- `transport`: ノード間の通信、TLSにより保護(HTTPを用いていない)

また、`ELASTIC_PASSWORD`にて`elastic`アカウントのパスワードも設定している。

## 動作確認

ここまでできたら準備完了なので、動作確認する。

```sh
$ docker-compose up -d
# 立ち上がるまで待った後、以下を実行
$ curl --cacert certs/ca/ca.crt -u 'elastic' https://localhost:9200
Enter host password for user 'elastic':
{
  "name" : "3fcf20ffb466",
  "cluster_name" : "docker-cluster",
  "cluster_uuid" : "_na_",
  "version" : {
    "number" : "8.5.0",
    "build_flavor" : "default",
    "build_type" : "docker",
    "build_hash" : "c94b4700cda13820dad5aa74fae6db185ca5c304",
    "build_date" : "2022-10-24T16:54:16.433628434Z",
    "build_snapshot" : false,
    "lucene_version" : "9.4.1",
    "minimum_wire_compatibility_version" : "7.17.0",
    "minimum_index_compatibility_version" : "7.0.0"
  },
  "tagline" : "You Know, for Search"
}
```

{{% notice note "ノードの再起動にあたって" %}}
ノードの再起動を行う場合、`cluster.initial_master_nodes`は予め削除しておくことが望ましい。
これは、`cluster.initial_master_nodes`はクラスタの初回起動時にのみ必要な設定であり、
残したままにしておくと再起動時に悪影響を及ぼす可能性があるためである。
{{% /notice %}}

# まとめ

今回はシングルノード構成で永続化を達成するため、クラスタの初期設定とX-Packセキュリティのセットアップを自力で行った。

今回のセットアップでも一応Elasticsearchの機能は利用できるが、
基本的にElasticsearchは複数ノードでの動作を前提している部分が多い。
そこで、次回はマルチノードの構成、および本番利用に耐えうるコンテナの設定を行っていこうと思う。







