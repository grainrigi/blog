---
title: "Goのジェネリクスでnew(T)したら「type *T is pointer to type parameter, not type parameter」と怒られた" # Title of the blog post.
date: 2022-12-11T22:24:05+09:00 # Date of post creation.
# menu: main
usePageBundles: false # Set to true to group assets like images in the same folder as this post.
featureImage: "/images/golang.png" # Sets featured image on blog post.
thumbnail: "/images/golang.png" # Sets thumbnail image appearing inside card on homepage.
categories:
  - 技術記事
tags:
  - Golang
# comment: false # Disable comment if false.
---

# TL;DR

- Goのジェネリクスの制約はその型自身にのみかけることができ、派生するポインタに関して直接制約をかけることはできない
- ただし、型パラメータの推論をうまく使うことで擬似的に制約をかけることが可能

---

Go 1.18 で導入された generics だが、ポインタの絡む型を扱っている際に奇妙なエラーに悩まされることがある。

例えば、以下のように特定のインターフェースを実装した型を new して返すような関数を作ってみる。

```go {linenos=table}
package main

import "time"

type Initializable interface {
	Initialize()
}

func CreateResource[T Initializable]() *T {
	r := new(T)
	r.Initialize()
	return r
}

// Initializableを実装してみた型
type SomeResource struct {
	creationTime time.Time
}
func (r *SomeResource) Initialize() {
	r.creationTime = time.Now()
}

// ...
```

`CreateResource`は、「リソースの構造体を作る→その値の初期化」という一連の流れを共通化するための関数である。
`Initialize`メソッドに初期化処理を書くように定め、`Initializable`インターフェースでそのことを示している。
実際に初期化する際には`CreateResource[SomeResource]()`のようにして呼び出す、という想定である。
中でポインタを作成しているのは、Initializeメソッドが自身の値を変更できるようにするためである。
(Initializeメソッドがポインタレシーバで定義されることを期待している)

しかし、このコードはコンパイル時に以下のエラーが発生する。

```
./generics.go:11:4: r.Initialize undefined (type *T is pointer to type parameter, not type parameter)
```

一見するとなぜエラーとなるのかがわかりにくいのだが、Go の型システムについて正しく理解すると原因が分かるようになる。

# なぜダメだったのか

エラーになった`CreateResource[T]`をもう一度よく見てみよう。

```go
func CreateResource[T Initializable]() *T {
	r := new(T)
	r.Initialize()
	return r
}
```

最初に`new(T)`で`T`を作成している。`new`はポインタを返すので、`r`の型は`*T`である。
一方、型パラメータにおいて、`[T Initializable]`という記述は、`T`については`Initializable`を実装していることを言っている一方、
**`*T`に関しては何も言っていない。** つまり、rに関して何の操作ができるのかコンパイラには何もわからないので、
その下の行での`r.Initialize()`がエラーになるのである。

しかしこう思うかもしれない。「普通はTがメソッドを実装していたら*Tに対しても同じメソッド呼べますよね？」と。
実際、以下のようなコードは普通に機能する。

```go
type Fuga struct {} 

func (f Fuga) Hoge() {}

func main() {
	fp := new(Fuga)
	fp.Hoge()
}
```

このコードでは値型である`Fuga`に対して`Hoge`メソッドを実装しているが、
`Fuga`のポインタ`fp`に対し、`fp.Hoge()`というふうに値型で定義したメソッドを呼び出すことが出来ている。
これは一見すると`Hoge`メソッドが値型とポインタ型の両方で自動的に共有されたかのように思えてしまうが、
実際にはそうはなっていない。

そもそもGoのメソッド呼び出し構文はただのシンタックスシュガーで、実際には以下のように展開される。

```go
type Fuga struct {} 

func (f Fuga) Hoge() {}

func main() {
	fp := new(Fuga)
	Fuga.Hoge(*fp)
}
```

このように、ポインタから値レシーバのメソッドを呼び出す際には、メソッドに自身を渡す際に**内部的に逆参照を行っている**のである。
つまり、結局のところ`*Fuga`を受け取るメソッドは存在せず、
呼び出し側でうまいことメソッドのレシーバ型に合わせて逆参照を行っているだけなのである。

つまり何が言いたいかと言うと、**ある型についてinterfaceの実装は値型かポインタ型のいずれかに対してしか出来ない**ということである。
実装しなかった側の型はinterfaceの制約を満たすことはない。

より具体的にするため、以下の例を見てみよう。

```go
type Interface interface {
	Func()
}

// 値型に対しInterfaceを実装
type ValueImplemented struct{}
func (v ValueImplemented) Func()

// ポインタ型に対しInterfaceを実装
type PointerImplemented struct{}
func (p *PointerImplemented) Func()

func UseInterface(i Interface) {}


func main() {
	valuev := ValueImplemented{}
	valuep := PointerImplemented{}
	pointerv := new(ValueImplemented)
	pointerp := new(PointerImplemented)

	UseInterface(valuev)    // 値型でinterfaceを実装し、値を渡す→OK
	UseInterface(valuep)    // ポインタ型でinterfaceを実装し、値を渡す→NG
	UseInterface(pointerv)  // 値型でinterfaceを実装し、ポインタを渡す→本来はNGだがinterfaceへの変換時に値に直されるのでOK
	UseInterface(pointerp)  // ポインタ型でinterfaceを実装し、ポインタを渡す→OK
}
```

今までの話を踏まえれば、上記の例では、`ValueImplemented`と`*PointerImplemented`がinterface`Interface`を実装し、
`*ValueImplemented`と`*PointerImplemented`は`Interface`を実装していないということになる。

※ 実際には`*ValueImplemented`を`Interface`として取り扱おうとしても許される。(コード中の`UseInterface(pointerv)`)
これは、`ValueImplemented`は値レシーバで`Interface`を実装しているため、
`*ValueImplemented`においても逆参照するだけで`Interface`を実装している型(`ValueImplemented`)に戻すことができるためである。


# CreateResourceを修正する

インターフェースの実装ルールについて理解したところで、再度`CreateResource`の例に戻ってみる。

```go
func CreateResource[T Initializable]() *T {
	r := new(T)
	r.Initialize()
	return r
}

// Initializableを実装してみた型
type SomeResource struct {
	creationTime time.Time
}
func (r *SomeResource) Initialize() {
	r.creationTime = time.Now()
}
```

`SomeResource`をよく見てみると、`*SomeResource`に対しては`Initialize`が実装されているものの、
`SomeResource`には`Initialize`が実装されていない。
つまり、今回のシナリオ通りに`T`に`SomeResource`を渡そうとしても、そもそも`Initializable`ではないのだから制約を満たさずエラーになってしまうのである。
(実際に`CreateResource[SomeResource]()`の呼び出しを記述するとエラーになる)

つまり、そもそもTにかけるべき制約は`Initializable`ではなかったのである。
実際にかけたい制約は「Tの*ポインタ型が*Initializableを実装している」という制約である。
しかし、GoのGenericsにそのような制約を書く手段は存在しない。

よって、とりあえず動くようにする解決策としては「`T`を`any`にしてしまい、`*T`に`Initialize`が実装されていることを信じる」という方法がある。
これは以下のように書くことができる。

```go
func CreateResource[T any]() *T {
	r := new(T)
	interface{}(r).(Initializable).Initialize()
	return r
}
```

## 第二の型パラメータを利用したトリック

しかし、当然上記のような解決策では満足しないだろう。
これでは折角の型安全性が台無しである。

実は、以下のように2つめの型パラメータをうまく定義してやることで型安全性を保ったままこの問題を解決できる。

```go
func CreateResource[T any, PT interface { Initializable; *T }]() *T {
	r := PT(new(T))
	r.Initialize()
	return (*T)(r)
}
```

`PT`という型パラメータが増えている。`interface { Initializable; *T }`という記述は初見だと面食らうのだが、
これは型パラメータ特有の記法で、中に型名を並べて書くことで、記述した全ての型の積集合を表すことができる。
この場合、`Initializable`を実装しており、かつ`*T`であるような型ということになる。
つまり、型パラメータ`PT`を推論するには、`*T`かつ`Initializable`な型が作成可能であること、
**即ち`*T`が`Initializable`を実装していること**が絶対条件となる。
(もし`T`に`Initializable`でない型を渡すと、積集合が空になって`PT`の推論に失敗する)
これにより、間接的に`*T`に対して制約をかけることができているのである。

次に、関数内での動きに注目してみよう。

関数内で`*T`の値を作り出したら、まずは`PT`にキャストする。
これにより、`*T`かつ`Initializable`であることがわかった状態で`r`を触ることができ、本来の目的を達成できる。
また、`PT`自体は実質的には`*T`と等価であるもののコンパイラ的には別の型なので、
返却する際には明示的に`*T`に戻している。

このように、第二の型パラメータの推論時のチェックを活用することで、型安全性を保ったままポインタ型に制約をかけることができる。


# 参考文献

[Go with Generics: type *T is pointer to type parameter, not type parameter - Stack Overflow](https://stackoverflow.com/questions/71444847/go-with-generics-type-t-is-pointer-to-type-parameter-not-type-parameter)

[Go 1.18 Generics how to define a new-able type parameter with interface - Stack Overflow](https://stackoverflow.com/questions/71440697/go-1-18-generics-how-to-define-a-new-able-type-parameter-with-interface)
