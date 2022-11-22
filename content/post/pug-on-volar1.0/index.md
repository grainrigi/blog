---
title: "Volar1.0でPugのTypeScript補完が効くようにする" # Title of the blog post.
date: 2022-11-22T17:52:44+09:00 # Date of post creation.
usePageBundles: true # Set to true to group assets like images in the same folder as this post.
featureImage: "vue.png" # Sets featured image on blog post.
thumbnail: "vue.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - 技術記事
tags:
  - Vue.js
# comment: false # Disable comment if false.
---

Vue3がリリースされてから早2年、周辺のライブラリやエコシステムもかなり使えるレベルに進化してきている。
その中でも、[Volar](https://github.com/johnsoncodehk/volar)というVSCode拡張を用いると、
`<template>`ブロック内でTypeScriptベースの補完を効かせることが可能となる。

{{<image src="volar-normal.png" h="250" title="importしたコンポーネントが緑色で表示され、propsが自動でサジェストされている">}}

しかし、`<template lang="pug">`を用いると、以下のようにTypeScriptの補完が効かなくなってしまう。

{{<image src="volar-pug-nw.png">}}

## 原因

Volarは直近(22年9月)に1.0がリリースされたのだが、この際にpugのサポートが別パッケージに分離されたらしい。

[volar/CHANGELOG.md at master · johnsoncodehk/volar](https://github.com/johnsoncodehk/volar/blob/master/CHANGELOG.md#100-alpha0-2022916)

このため、プロジェクト自体にpugサポート用のパッケージをインストールし、これを用いるように設定する必要がある。

## pugサポートをインストールする

まず、`@volar/vue-language-plugin-pug`をインストールする。

```sh
$ yarn add -D @volar/vue-language-plugin-pug
```

次に、`tsconfig.json`に`vueCompilerOptions`を追加し、このプラグインを用いるようにする。

```json
{
  "vueCompilerOptions": {
    "plugins": ["@volar/vue-language-plugin-pug"]
  }
}
```

自分の手元では`tsconfig.json`を保存した時点でpug上の補完が効くようになった。

{{<image src="volar-pug-working.png" h="242">}}

