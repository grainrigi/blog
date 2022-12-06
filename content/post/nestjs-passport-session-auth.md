---
title: "NestJS + Passport.jsを使って普通のCookieベースセッションの認証を実装する" # Title of the blog post.
date: 2022-12-06T22:06:24+09:00 # Date of post creation.
description: "NestJSとPassport.jsプラグインを用いると認証を実現できますが、公式ガイドではJWTを用いた方法のみが解説されています。本記事では、Cookieベースの認証を実装する方法を解説します。" # Description used for search engine.
featureImage: '/images/nestjs.svg'
thumbnail: '/images/nestjs.svg'
categories:
  - 技術記事
tags:
  - NestJS
  - TypeScript
---

NestJS公式でサポートされるアカウント認証フレームワークにPassport.jsがある。
Passport.jsを使った認証の実装は`@nestjs/passport`というプラグインを使って容易に実装することができ、
公式ガイドの[Authentication | NestJS](https://docs.nestjs.com/security/authentication)にはこのプラグインを使って認証を組み込む方法が解説されている。

しかしながら、この公式ガイドで解説されているのはあくまでクライアント側でJWTを使用する方法であり、
いわゆる普通のCookieセッションを使った認証の実装方法は解説されていない。
そこで、本記事ではNestJSとPassport、およびexpress-sessionを使ってCookieセッションを実装する方法を取り上げる。

# TL;DR

セッションを実装するには以下の点に気をつける必要がある。

- セッションを有効化するには`AuthGuard.logIn`を呼び出す必要があるため、`AuthGuard`を継承し`canActivate`内で`super.logIn`を呼び出す
- セッションデータ(文字列)とユーザーオブジェクトを変換するためにSerializerを実装する(`PassportSerializer`を継承)


# 実装手順

セッションベース認証の実装方法は概ね以下のようになる。

1. 自サービスのユーザー認証を呼び出すStrategyを実装(`@nestjs/passport/PassportStrategy`を継承)
2. 1のStrategyを使って、ログイン認証用のGuardを実装(`@nestjs/passport/AuthGuard`を継承)
3. `express-session`を設定するModuleを作成
4. ユーザー情報をセッションデータから復元するSerializerを実装(`@nestjs/passport/PassportSerializer`を継承)

色々と新しい用語が出てきているが、追って説明する。

## 前準備: authモジュールの作成

各種実装に先立って、ログイン処理を実装するモジュールとして`auth`モジュールを作成する。

```sh
$ nest g mo auth
```

さらに、`auth.module.ts`を編集して`PassportModule`をインポートする。

```ts:auth.module.ts
import { Module } from '@nestjs/common';
import { PassportModule } from '@nestjs/passport';

@Module({
  imports: [PassportModule.register({ session: true })],
})
export class AuthModule {}
```


## 1. Strategyの実装

StrategyはPassport.js内で使われる用語で、様々なユーザーの認証手段(ID/PASS認証やOAuth等)を抽象化した概念である。
また、Strategyを実装するための[様々なパッケージ](https://www.passportjs.org/packages/)が公式に提供されている。

今回は典型的なID/PASS認証を提供するStrategyである[passport-local](https://www.passportjs.org/packages/passport-local/)を使って実装を行う。

まずは必要なパッケージをインストールする。

```
$ npm install @nestjs/passport passport passport-local
```

次に、実際のユーザー・パスワードの照合を行う`AuthService`を作成する。

まずは以下のコマンドでファイルを生成する。

```
$ nest g s auth
```

そして、`auth.service.ts`を以下のように編集する。

```ts:auth.service.ts
import { Injectable } from '@nestjs/common';

@Injectable()
export class AuthService {
  async validateUser(email: string, password: string): Promise<User | null> {
    const user = // DBからユーザー情報を取得
    if (user?.checkPassword(password)) {
      return user;
    }
    return null;
  }
}

```

さらに、これを呼び出す形で`auth/local.strategy.ts`を以下の内容で作成する。

```ts:local.strategy.ts
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { Strategy } from 'passport-local';
import { AuthService } from './auth.service';

@Injectable()
export class LocalStrategy extends PassportStrategy(Strategy) {
  constructor(private authService: AuthService) {
    super();
  }

  async validate(email: string, password: string): Promise<User> {
    const user = await this.authService.validateUser(email, password);
    if (!user) {
      throw new UnauthorizedException();
    }
    return user;
  }
}

```

`validate`はStrategyから呼び出されるメソッドで、`passport-local`の場合、第一引数にID、第二引数にパスワードが渡される。
認証に成功した場合はユーザーを表すオブジェクトを返し、失敗した場合は`UnauthorizedException`を投げて401 Unauthorizedレスポンスを返している。

最後に、このStrategyを`auth`モジュールにProviderとして登録する。

```ts:auth.module.ts
import { Module } from '@nestjs/common';
import { AuthService } from './auth.service';
import { LocalStrategy } from './local.strategy';
import { PassportModule } from '@nestjs/passport';

@Module({
  imports: [PassportModule.register({ session: true })],
  providers: [AuthService, LocalStrategy],
})
export class AuthModule {}

```

## 2. ログイン処理用Guardの実装

次に、**ログイン処理そのもの**を実行するGuardを実装する。

`auth/local.guard.ts`を以下の内容で作成する。

```ts:local.guard.ts
import { ExecutionContext } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

export class LocalGuard extends AuthGuard('local') {
  async canActivate(context: ExecutionContext): Promise<boolean> {
    const result = (await super.canActivate(context)) as boolean;
    await super.logIn(context.switchToHttp().getRequest());
    return result;
  }
}
```

セッションを使わない場合は`AuthGuard('local')`を直接使えばいいのだが、
今回は`AuthGuard.logIn`を呼び出してセッションを有効化する必要があるため継承している。
`super.logIn`メソッドは、NestApplicationの実体(通常はexpress)のセッション機能を用いて新規セッションを作成するメソッドなのだが、
デフォルトではこのメソッドが呼び出されない。`express-session`をuseしただけではセッションが有効にならない(Cookieがセットされない)のはこのためである。

Guardが完成したら、ログイン用のエンドポイントに結びつける。

まずはControllerを作成する。

```
$ nest g co auth
```

さらに、以下のように編集する。

```ts:auth.controller.ts
import { Controller, Post, UseGuards } from '@nestjs/common';
import { LocalGuard } from './local.guard';

@Controller('auth')
export class AuthController {
  @UseGuards(LocalGuard)
  @Post('login')
  login() {
    return { result: 'ok' }; // LocalGuardが実際のログイン処理を行うので、成功時のレスポンスを返すだけ
  }
}
```

ここで先程作ったGuardをログインのエンドポイントに割り当てる。
これにより、`/auth/login`を呼び出すと`LocalGuard`によりIDパスワード認証が実行される。
`LocalGuard`(`AuthGuard('local')`)は`LocalStrategy`を内部で呼び出すため、
先程実装したように、認証失敗時には`UnauthorizedException`をスローする。
これにより、認証に成功した場合のみ`login`メソッドの内容が実行される。
今回はログインが成功したことを示す簡単なレスポンスを返している。

これにより、ログイン処理を行うエンドポイントが一応出来上がった。

## 3. express-sessionの設定

次に実際にセッションを管理する部分を設定する。今回はexpress-sessionとRedisを使ってセッション管理を行う。

まずは必要なパッケージをインストールする。

```sh
$ npm install express-session ioredis connect-redis
```

次に、`session`モジュールと`redis`モジュールを作成する。

```
$ nest new mo session
$ nest new mo redis
```

### redisモジュールの実装

redisモジュールでは、Redisインスタンスを提供できるようにする。

まずはRedisインスタンスを管理させるために`RedisService`を作成する。

以下のコマンドを実行してファイルを生成する。

```
$ nest new s redis
```

次に、`redis.service.ts`を以下のように編集する。

```ts:redis.service.ts
import { Injectable, OnModuleDestroy } from '@nestjs/common';
import Redis from 'ioredis';

@Injectable()
export class RedisService implements OnModuleDestroy {
  driver: Redis;

  constructor() {
    this.driver = new Redis({
      host: process.env.REDIS_HOST ?? 'localhost',
      port: process.env.REDIS_PORT ?? 6379,
    });
  }

  async onModuleDestroy() {
    await this.driver.disconnect();
  }
}
```

ポイントは`onModuleDestroy`を呼び出していることである。
これを呼び出さないと、`RedisModule`の終了後もコネクションが張りっぱなしになってしまうため、
E2Eテストを行った際などにNode.jsが終了しなくなってしまうことがある。

また、今回は簡単のため環境変数から設定値を取り出しているが、実際は`@nestjs/config`のConfigModule等を用いるのが良い。

次に、`redis.module.ts`を以下のように編集する。

```ts:redis.module.ts
import { Module } from '@nestjs/common';
import Redis from 'ioredis';
import { RedisService } from './redis.service';

@Module({
  providers: [
    RedisService,
    {
      provide: Redis,
      useFactory: async (redisService: RedisService) => redisService.driver,
      inject: [RedisService],
    },
  ],
  exports: [Redis],
})
export class RedisModule {}
```

これで`Redis`をDIできるようになった。

### sessionモジュールの実装

sessionモジュールでは、先程準備したRedisインスタンスを用いてexpress-sessionを設定する。

`session.module.ts`を以下のように編集する。

```ts:session.module.ts
import { Module } from '@nestjs/common';
import Redis from 'ioredis';
import { RedisModule } from '../redis/redis.module';
import expressSession from 'express-session';
import connectRedis from 'connect-redis';
import passport from 'passport';

@Module({
  imports: [SessionConfigModule, RedisModule],
})
export class SessionModule {
  constructor(
    private readonly redis: Redis,
  ) {}

  configure(consumer: MiddlewareConsumer) {
    const RedisStore = connectRedis(expressSession);

    consumer
      .apply(
        expressSession({
          secret: process.env.SESSION_SECRET,
          resave: false,
          saveUninitialized: false,
          cookie: {
            maxAge: 8 * 60 * 60 * 1000,
            secure: true,
          },
          store: new RedisStore({ client: this.redis }),
        }),
        passport.initialize(),
        passport.session(),
      )
      .forRoutes('*');
  }
}
```

`configure`メソッドをオーバーライドすることで、サーバーの実体(express)でuseしたいミドルウェアを登録することができる。
ミドルウェアを登録するには、第一引数に渡ってくるMiddlewareConsumerに対してapplyメソッドで渡してやればよい。

express-session自体は普通にexpressで使うときと同様に設定すれば良い。
その下にある`passport.initialize()`と`passport.session()`は、express上でPassport.jsを使う際に渡す必要のあるミドルウェアである。
今回はexpressのセッション機能とPassport.jsが直接やり取りをするためこれを記述する必要がある。

ちなみに、`passport.session()`を`expressSession(...)`より前に置くことは出来ない。
これは、`passport.session()`がセッション機構を初期化する際にexpress-sessionの有無を確認し、
存在する場合にのみexpress-sessionにアタッチするためである。

## 4. ユーザーデータのSerializerの作成

ログイン時にLocalStrategyで設定したUserオブジェクトは、ログインリクエストの終了時にセッションに紐づけて保存する必要がある。
このとき、Userオブジェクトを丸ごとセッションに保存するわけにはいかないので、
メモリ上のUserオブジェクトとセッションに保存する値を相互変換する必要がある。

この相互変換処理を実装するには、Serializerと呼ばれるオブジェクトを実装する必要がある。

以下の内容で`auth/auth.serializer.ts`を作成する。

```ts:auth.serializer.ts
import { Injectable } from '@nestjs/common';
import { PassportSerializer } from '@nestjs/passport';
import { Manager } from '@prisma/client';
import { ManagersService } from '../managers/managers.service';

export type SessionData = { id: number };

@Injectable()
export class AuthSerializer extends PassportSerializer {
  constructor(private managersService: ManagersService) {
    super();
  }

  serializeUser(
    user: Manager,
    done: (err: Error | null, user: SessionData) => void,
  ) {
    // IDのみを保存する
    done(null, { id: user.id });
  }

  async deserializeUser(
    payload: SessionData,
    done: (err: Error | null, user: Omit<Manager, 'hash'>) => void,
  ) {
    const user_id = payload.id;
    const user = // DBからユーザーデータを読み出す
    done(null, user!);
  }
}
```

`serializeUser`はセッションデータの保存時に呼ばれ、
`deserializeUser`はセッションデータの復元時に呼ばれる。

今回の実装では、セッションデータにはユーザーのidのみを保存し、
Userオブジェクトの復元時には保存したidを使って再度DBから読み出すようにしている。

あとは、このSerializerをProviderとして登録する。

```ts:auth.module.ts
import { Module } from '@nestjs/common';
import { PassportModule } from '@nestjs/passport';
import { AuthService } from './auth.service';
import { LocalStrategy } from './local.strategy';
import { AuthController } from './auth.controller';
import { AuthSerializer } from './auth.serializer';

@Module({
  imports: [PassportModule.register({ session: true })],
  providers: [AuthService, LocalStrategy, AuthSerializer],
  controllers: [AuthController],
})
export class AuthModule {}
```

これにより、Passport.jsがUserオブジェクトとセッションデータを相互変換できるようになった。


# セッションをアプリケーションで利用する

上記の手順により、Passport.jsによるセッションベースの認証が完成した。
今度はアプリケーションでこれを利用してみる。

## 認証済みかどうかのチェック

まずは認証済みかどうかをチェックするGuardを作成してみる。

`auth/loggedin.guard.ts`を以下の内容で作成する。

```ts:loggedin.guard.ts
import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';

@Injectable()
export class LoggedInGuard implements CanActivate {
  canActivate(context: ExecutionContext) {
    return context.switchToHttp().getRequest().isAuthenticated();
  }
}
```

`isAuthenticated`はPassport.jsによって生やされたメソッドで、これを使うことで現在のセッションが認証済みかどうかをチェックできる。

あとはこのGuardをエンドポイントに割り当てれば、未認証ユーザーを弾くことができる。

## セッションに紐付いたユーザーを取得

Passport.jsは`req.user`にUserオブジェクト(`deserializeUser`の結果)を格納するので、
単純にRequestオブジェクトを直接参照すれば取得できる。

```ts
  // 現在のユーザーを返す
  @Get('session')
  async session(@Req req: Request) {
    return req.user;
  }
```

ただ、実際には使い勝手が悪いので以下のようなデコレーターを作成するのが良いだろう。

```ts
import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { Manager } from '@prisma/client';

export const User = createParamDecorator(
  (data: unknown, ctx: ExecutionContext): User | null => {
    const req = ctx.switchToHttp().getRequest();
    return req.user;
  },
);
```

あとは、以下のように引数をデコレートすればUserオブジェクトを利用できる。

```ts
async session(@User() user: User | null) {
  // ...
}
```


# まとめ

非常に長くなってしまったが、以上の手順によりCookieベースのセッションを実装できる。

個人的にはこのあたりはもう少しちゃんと公式ドキュメントに記述されていてほしいところではある。



# 参考文献

[Setting Up Sessions with NestJS, Passport, and Redis - DEV Community 👩‍💻👨‍💻](https://dev.to/nestjs/setting-up-sessions-with-nestjs-passport-and-redis-210)
