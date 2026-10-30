# CP4 Trigger Recipes 詳細設計書

## 目次

1. [文書情報](#1-文書情報)
2. [要件](#2-要件)
3. [対象範囲](#3-対象範囲)
4. [コンポーネント設計](#4-コンポーネント設計)
5. [共通TriggerHandler 最終詳細設計](#5-共通triggerhandler-最終詳細設計)
6. [CaseTrigger 最終詳細設計](#6-casetrigger-最終詳細設計)
7. [CaseTriggerHandler 最終詳細設計](#7-casetriggerhandler-最終詳細設計)
8. [CaseEscalationService 最終詳細設計](#8-caseescalationservice-最終詳細設計)
9. [関連自動化・再入・非機能要件](#9-関連自動化再入非機能要件)
10. [テスト最終設計](#10-テスト最終設計)
11. [代替設計比較と責務境界](#11-代替設計比較と責務境界)
12. [実装・検証状態](#12-実装検証状態)
13. [設計判断履歴](#13-設計判断履歴)

## 1. 文書情報

| 項目 | 内容 |
| --- | --- |
| 対象CP | CP4 Trigger Recipes |
| 練習要件 | Caseエスカレーション自動化 |
| 状態 | Gate B 100%・本人設計完了／Gate C 100%（6/6）完了／Gate D証拠監査待ち |
| 最終更新日 | 2026-10-05 |
| 作業ブランチ | `feature/cp4-trigger-recipes` |
| 根拠 | `GOAL_SPEC.md`、`PLAN.md`、本人によるGate A・Gate B説明 |

この文書は、ユーザー本人が説明して確定した設計を実装契約として整理する。AIが作成した要約だけでは本人理解・実装・テスト成功の証拠としない。未回答の判断は推測で補わず、`未確定`と記載する。

## 2. 要件

- 既存CaseのStatusが別の値から`Escalated`へ変わった場合だけ処理する。
- AccountIdがない対象Caseは保存を拒否する。
- 保存可能な対象CaseはPriorityを`High`へ補正する。
- Caseの保存成功後、対象Caseごとに確認Taskを1件作成する。
  - WhatId: Case Id
  - OwnerId: Case OwnerId
  - Subject: `Review escalated case`
- すでに`Escalated`のCaseで別項目だけを更新した場合は対象外とする。
- Status=`Escalated`で新規insertされたCaseは対象外とする。
- 最大200件を一括処理できる構成とする。
- 1オブジェクト1Triggerとし、Trigger、個別Handler、Serviceへ責務を分離する。

## 3. 対象範囲

### 対象

- 直接dispatch方式の共通`TriggerHandler`
- Caseの`before update`と`after update`
- Status遷移判定
- AccountId検証と`addError()`
- Priority補正
- Taskの一括生成・登録
- context dispatch、trigger外実行、bypass、loop countの共通基盤テスト
- Case業務処理の正常、複数、対象外、異常、部分成功、再入・重複防止テスト
- Case更新後にDescriptionを補正して同一トランザクション再入を発生させるafter-saveレコードトリガーフロー。CP4の学習要件として実メタデータを作成し、Git管理・デプロイ・テスト対象にする

### 対象外

- Metadata／Custom Metadataによる動的dispatch
- Platform Event Trigger対応
- Status=`Escalated`でのCase insert処理
- 上限超過データの分割、非同期化、再試行
- CP4要件と無関係な既存クラスの変更

## 4. コンポーネント設計

| コンポーネント | 責務 | 責務外 |
| --- | --- | --- |
| `CaseTrigger` | Case updateイベントの入口、`CaseTriggerHandler`の起動 | 業務判定、DML、bypass状態管理 |
| `TriggerHandler` | 共通context判定・dispatch、実行回数、bypassの管理 | Case固有の業務ルール |
| `CaseTriggerHandler` | Trigger context値の取得・保持、イベントに応じたService呼出し | Status遷移判定、AccountId検証、Priority補正、Task生成・DML |
| `CaseEscalationService` | Status遷移判定、対象Caseの検証・補正、確認Taskの生成・一括登録 | Triggerイベントのdispatch |

## 5. 共通TriggerHandler 最終詳細設計

この章を`TriggerHandler`実装契約の正本とする。2026-09-23〜25の回答履歴に含まれていた旧案、訂正前のmax境界、古い例外メッセージは正本として使用しない。

### 5.1 責務とクラス方針

| 項目 | 最終仕様 |
| --- | --- |
| クラス宣言 | `public virtual with sharing class TriggerHandler` |
| 主責務 | `Trigger.operationType`の判定、context別hookへのdispatch、Trigger外実行の検出、Handler単位のbypass・loop count管理 |
| 責務外 | Case固有の業務条件、対象レコード抽出、SOQL、DML、Task重複防止の業務判定 |
| `virtual` | 個別Handlerが7つのcontext hookをoverrideできるようにする。抽象クラスにはせず直接生成を禁止しない |
| `with sharing` | 将来レコードアクセスが追加された場合の安全な既定値と、共有を尊重する設計意図を明示する |
| `run()` | 共通dispatch手順を固定するため非virtual |
| 重複防止との関係 | CaseのTask重複防止はloop上限やbypassではなく、ServiceのStatus遷移条件を主とする |

### 5.2 内側型

#### TriggerContext

- 宣言: `@TestVisible private enum TriggerContext`
- 値: `BEFORE_INSERT`、`BEFORE_UPDATE`、`BEFORE_DELETE`、`AFTER_INSERT`、`AFTER_UPDATE`、`AFTER_DELETE`、`AFTER_UNDELETE`
- 用途: Salesforceの`Trigger.operationType`を、`run()`がdispatchする内部contextへ対応付ける。

#### TriggerHandlerException

- publicな内側例外クラス。
- Trigger外からの`run()`、未対応Trigger context、loop上限超過に使用する。

#### LoopCount

| 項目 | 最終仕様 |
| --- | --- |
| 宣言 | `@TestVisible private`な内側クラス |
| fields | `private Integer max`、`private Integer count` |
| constructor | `public LoopCount(Integer max)`。受け取ったmaxを保持し、countを0で初期化 |
| `increment()` | public、引数なし、戻り値`Boolean`。countを1増やした後、上限超過結果を返す |
| `exceeded()` | public、引数なし、戻り値`Boolean`。`max >= 0 && count > max`でtrue |
| `getMax()` | public、引数なし、戻り値`Integer` |
| `getCount()` | public、引数なし、戻り値`Integer` |
| `setMax(Integer max)` | public、戻り値`void`。countは変更しない |

### 5.3 fieldsとstatic状態

| field | 可視性・static | 初期化 | 用途 |
| --- | --- | --- | --- |
| `context` | private instance `TriggerContext` | constructor内のcontext設定 | 現在のTriggerイベント |
| `isTriggerExecuting` | private instance `Boolean` | `Trigger.isExecuting` | Trigger外からの`run()`を検出 |
| `bypassedHandlers` | private static `Set<String>` | field宣言時に空Set | Handler名単位のbypass |
| `loopCountMap` | private static `Map<String, LoopCount>` | field宣言時に空Map | Handler名単位のcountとmax |

static状態は同一トランザクション内で共有し、Handler名ごとに分離する。別トランザクションへは引き継がれない。

### 5.4 constructorとcontext設定

| API | 最終仕様 |
| --- | --- |
| `public TriggerHandler()` | `setTriggerContext()`を呼び、実行場所とcontextを初期化する |
| `private void setTriggerContext()` | `isTriggerExecuting=Trigger.isExecuting`とする。trueなら`Trigger.operationType`を7つの`TriggerContext`へ対応付ける。falseならcontextを設定せず、`run()`時にTrigger外例外とする |
| `@TestVisible private void setTriggerContextForTest(TriggerContext testContext)` | nullを拒否し、非nullならcontextへ設定して`isTriggerExecuting=true`とする |

未対応の`Trigger.operationType`に到達した場合は`TriggerHandlerException`を送出する。メッセージ形式は`Unsupported Trigger context: {Trigger.operationType}`。

### 5.5 メソッドAPI

| メソッド | 可視性 | static／instance | 引数 | 戻り値 | 最終契約 |
| --- | --- | --- | --- | --- | --- |
| `run()` | public | instance・非virtual | なし | `void` | 実行可否確認、loop加算、context hook dispatchを順番に行う |
| `bypass()` | public | static | `String handlerName` | `void` | 検証後、Handler名をbypass対象へ追加 |
| `clearBypass()` | public | static | `String handlerName` | `void` | 検証後、Handler名をbypass対象から削除 |
| `isBypassed()` | public | static | `String handlerName` | `Boolean` | 検証後、Handler名がbypass中か返す |
| `setMaxLoopCount()` | public | instance | `Integer max` | `void` | 検証後、現在Handlerのmaxを設定。既存countは初期化しない |
| `clearMaxLoopCount()` | public | instance | なし | `void` | 現在Handlerのmaxを`-1`として上限を無効化。既存countは維持 |
| `validateRun()` | private | instance | なし | `Boolean` | Trigger外なら例外、bypass中ならfalse、それ以外はtrue |
| `addLoopCount()` | private | instance | なし | `void` | 設定済みHandlerのcountを増やし、上限超過なら例外 |
| `getHandlerName()` | private | instance | なし | `String` | 実行中インスタンスから具体的Handler名を取得 |
| `validateHandlerName()` | private | static | `String handlerName` | `void` | bypass API共通のHandler名検証 |
| `validateMaxLoopCount()` | private | static | `Integer max` | `void` | maxのnull・範囲検証 |

7つのhookはすべてprotected virtual、引数なし、戻り値`void`、既定動作なしとする。

| hook | 対応context |
| --- | --- |
| `beforeInsert()` | `BEFORE_INSERT` |
| `beforeUpdate()` | `BEFORE_UPDATE` |
| `beforeDelete()` | `BEFORE_DELETE` |
| `afterInsert()` | `AFTER_INSERT` |
| `afterUpdate()` | `AFTER_UPDATE` |
| `afterDelete()` | `AFTER_DELETE` |
| `afterUndelete()` | `AFTER_UNDELETE` |

### 5.6 run処理順

1. `validateRun()`でTrigger実行中か確認する。Trigger外なら例外を送出する。
2. 現在の具体的Handler名がbypass中か確認する。bypass中なら`run()`を終了する。
3. `addLoopCount()`でHandler別countを加算し、最大回数を超えていればhookを呼ぶ前に例外を送出する。
4. `context`に対応する7つのhookのうち1つだけを呼び出す。

bypass中はhookを呼ばず、loop countも消費しない。`run()`自体はoverrideさせず、個別Handlerは必要なhookだけをoverrideする。

### 5.7 bypass契約

- `bypass`、`clearBypass`、`isBypassed`はすべて最初に`validateHandlerName()`を呼ぶ。
- null、空文字、空白だけのHandler名は`IllegalArgumentException`とする。
- 完全なメッセージは`Handler name must not be blank.`。
- bypass状態はstatic SetでHandler名ごとに分離する。あるHandlerのbypassは別Handlerへ影響しない。
- テスト等で一時的にbypassする場合、`finally`で`clearBypass()`を実行して後続処理へ状態を残さない。

### 5.8 loop count契約

- max未設定時は無制限。
- 有効なmaxは、上限解除を表す`-1`または正の整数だけ。
- max=1では1回目を許可し、2回目はcountを増やした後、hook前に上限超過例外とする。
- max=2では2回目まで許可し、3回目に同じ例外とする。
- 上限超過メッセージは`Maximum loop count of {max} reached in {handlerName}`。
- `clearMaxLoopCount()`はmaxだけを`-1`へ変更し、countを初期化しない。
- `setMaxLoopCount()`でmaxを再設定しても、それまでのcountを維持する。同一トランザクション内の通算実行回数を判定するため。
- 例: max=2で2回実行、clear後に3回実行するとcount=5。max=3を再設定した後の次回`run()`はcount=6となり、hook前に上限超過例外を送出する。
- Handler名ごとに別の`LoopCount`を管理し、一方の上限到達は別Handlerへ影響しない。

### 5.9 入力境界と例外一覧

| 条件 | 例外型 | 完全なメッセージ／形式 |
| --- | --- | --- |
| Handler名がnull・空・空白 | `IllegalArgumentException` | `Handler name must not be blank.` |
| maxがnull | `IllegalArgumentException` | `Maximum loop count must not be null.` |
| maxが0または-2以下 | `IllegalArgumentException` | `Maximum loop count must be -1 or a positive integer.` |
| テスト用contextがnull | `IllegalArgumentException` | `Trigger context must not be null.` |
| Trigger外から`run()` | `TriggerHandler.TriggerHandlerException` | `Trigger handler called outside of Trigger execution` |
| 未対応Trigger context | `TriggerHandler.TriggerHandlerException` | `Unsupported Trigger context: {Trigger.operationType}` |
| loop上限超過 | `TriggerHandler.TriggerHandlerException` | `Maximum loop count of {max} reached in {handlerName}` |

### 5.10 テスト・実測境界

- `TriggerHandlerTest`では、内側の`RecordingTriggerHandler`と`SecondaryRecordingTriggerHandler`を使い、7イベントdispatch、Trigger外実行、bypassと解除、Handler別bypass分離、loop上限内・超過、Handler別count分離を確認する。具体的テスト契約は第10章を正本とする。
- `setTriggerContextForTest()`はテスト専用であり、本番コードのcontext指定には使用しない。
- `getHandlerName()`がトップレベル／テスト内側クラスをどの文字列で返すかはAPI 67.0で実測する。Handler名を含む例外メッセージの最終期待値もその実測に合わせる。
- 本章は設計証拠であり、未追跡の`TriggerHandler.cls`、コンパイル、テスト、デプロイ成功の証拠ではない。これらはGate C／Dで確認する。

## 6. CaseTrigger 最終詳細設計

### 6.1 宣言と責務

| 項目 | 最終仕様 |
| --- | --- |
| Trigger名 | `CaseTrigger` |
| 対象オブジェクト | `Case` |
| 宣言イベント | `before update`、`after update`のみ |
| 主責務 | contextごとに`CaseTriggerHandler`を引数なしで1インスタンス生成し、`run()`を1回呼ぶ |
| sharing | Trigger自体にはsharing宣言を付けない |
| 例外 | catchしない。Handler／Service／Task DMLの例外を起点のCase DML呼出元へ伝播する |
| 行わない処理 | Status遷移判定、Priority補正、Task生成・DML、SOQL、bypass・loop count管理 |

insert、delete、undeleteを宣言しない。今回の要件は、保存済みCaseが非`Escalated`から`Escalated`へ変更されるupdateだけを対象とするため。

### 6.2 context別処理

| context | Triggerの処理 |
| --- | --- |
| before update | `CaseTriggerHandler`を生成して`run()`を1回呼ぶ。親Handlerが`beforeUpdate()`へdispatchする |
| after update | `CaseTriggerHandler`を生成して`run()`を1回呼ぶ。親Handlerが`afterUpdate()`へdispatchする |

Triggerからnew Listやold Mapを引数として渡さない。`CaseTriggerHandler` constructorが`Trigger.new`と`Trigger.oldMap`を取得することで、Triggerの入口責務をHandler起動だけに限定する。

## 7. CaseTriggerHandler 最終詳細設計

### 7.1 クラスとfields

| 項目 | 最終仕様 |
| --- | --- |
| クラス宣言 | `public with sharing class CaseTriggerHandler extends TriggerHandler` |
| `newCases` | `private final List<Case>`。型変換した`Trigger.new`の参照を保持 |
| `oldCasesById` | `private final Map<Id, Case>`。型変換した`Trigger.oldMap`の参照を保持 |
| instance状態 | 上記2 fieldのみ |

`final`はList／Map参照の再代入を防ぐ。before updateで`newCases`内のCase項目を補正することは妨げない。

### 7.2 constructorとoverride

| API | 最終仕様 |
| --- | --- |
| public引数なしconstructor | `Trigger.new`と`Trigger.oldMap`をCase型へ変換し、2 fieldへ保持する。constructor自身は例外をcatch・送出しない |
| `protected override void beforeUpdate()` | `CaseEscalationService.validateAndSetPriorityForEscalations(newCases, oldCasesById)`を呼ぶ |
| `protected override void afterUpdate()` | `CaseEscalationService.createReviewTasksForEscalations(newCases, oldCasesById)`を呼ぶ |

他の5 hooksはoverrideしない。イベント追加が必要になった時点で別途設計する。

### 7.3 Handler境界

- Status遷移判定、AccountId検証、Priority補正、Task生成は行わず、Serviceへ委譲する。
- 空判定と対象抽出もHandlerでは行わない。
- Service例外をcatchせず、Trigger境界の外側へ伝播させる。
- loop上限を設定しない。正常なbefore／afterとFlow再入を単純な回数だけで異常再帰と区別できないため。
- bypass判定は親`TriggerHandler.run()`へ任せる。
- Trigger外でconstructorだけを呼ぶことは許容する。通常の`run()`は親が`TriggerHandlerException`、`Trigger handler called outside of Trigger execution`を送出し、Serviceへ到達しない。
- テスト用contextだけを強制して親検証を通過させた特殊経路ではfieldがnullのため、Serviceの先頭検証が`New Case list must not be null.`を送出する。

## 8. CaseEscalationService 最終詳細設計

### 8.1 クラスとAPI

| 項目 | 最終仕様 |
| --- | --- |
| クラス宣言 | `public with sharing class CaseEscalationService` |
| instance状態 | 持たない |
| constructor | private。外部からの生成を禁止 |
| before API | `public static void validateAndSetPriorityForEscalations(List<Case> newCases, Map<Id, Case> oldCasesById)` |
| after API | `public static void createReviewTasksForEscalations(List<Case> newCases, Map<Id, Case> oldCasesById)` |
| SOQL | 0回 |

### 8.2 private helper

| helper | 可視性・static | 戻り値 | 責務 |
| --- | --- | --- | --- |
| `validateCaseUpdateInputs(List<Case> newCases, Map<Id, Case> oldCasesById)` | private static | `void` | new List、old Map、各要素とId対応の構造検証 |
| `selectCasesTransitioningToEscalated(List<Case> newCases, Map<Id, Case> oldCasesById)` | private static | `List<Case>` | Status遷移対象を入力順で抽出。対象なしは空List |
| `validateAccountIdsAndSelectValidCases(List<Case> escalationCases)` | private static | `List<Case>` | 構造検証・Status遷移抽出済みの対象CaseについてAccountIdを検証。nullならCaseへ`addError()`を設定し、有効なら入力順で戻り値Listへ追加 |

構造検証、Status遷移判定、AccountId業務検証を分離する。両public APIは同じ3 helperを利用し、before／afterで入力境界、遷移条件、AccountId検証を重複実装しない。AccountId検証を共通化する理由は、将来の変更時に片方だけが修正される不整合を防ぐため。

### 8.3 構造入力検証

検証順序は次のとおり。全件の構造検証が完了するまでPriority補正、`addError()`、Task生成を開始しない。

1. `newCases == null`
2. `oldCasesById == null`
3. `newCases`を入力順に全件検証
   1. 要素がnull
   2. new Case Idがnull
   3. old Mapにnew Case Idのキーがない
   4. old Mapの対応Caseがnull

| 状態 | 例外型 | 完全なメッセージ |
| --- | --- | --- |
| new List null | `IllegalArgumentException` | `New Case list must not be null.` |
| old Map null | `IllegalArgumentException` | `Old Case map must not be null.` |
| List内null | `IllegalArgumentException` | `New Case must not be null. inputIndex={n}` |
| new Case Id null | `IllegalArgumentException` | `New Case Id must not be null. inputIndex={n}` |
| old MapにIdなし | `IllegalArgumentException` | `Old Case map does not contain the new Case Id. inputIndex={n}, caseId={Id}` |
| old Mapの対応値null | `IllegalArgumentException` | `Old Case must not be null. inputIndex={n}, caseId={Id}` |

`newCases=[]`かつold Map非nullなら、helper完了後にpublic APIが正常終了する。`newCases=[]`かつold Map nullなら、空判定より必須引数検証を優先し、old Map null例外とする。

### 8.4 Status遷移抽出

対象条件は次のAND条件とする。

- 更新前Statusが`Escalated`ではない。
- 更新後Statusが`Escalated`である。

| 更新・操作 | 判定 |
| --- | --- |
| `New → Escalated` | 対象 |
| `Working → Escalated` | 対象 |
| `Escalated → Escalated` | 対象外 |
| `Escalated → Working／Closed` | 対象外 |
| `New → Working` | 対象外 |
| Status=`Escalated`でinsert | Triggerイベント自体が対象外 |

抽出結果はnew Listの入力順を維持する。対象外CaseはAccountId検証、Priority補正、`addError()`、Task生成のいずれも行わない。

### 8.5 before API処理順

1. `validateCaseUpdateInputs()`で全構造を検証する。
2. new Listが空なら正常終了する。
3. `selectCasesTransitioningToEscalated()`で対象を抽出する。
4. 対象が空なら正常終了する。
5. 対象CaseすべてのAccountIdを確認する。
   - AccountIdなし: `addError()`を設定し、Priorityを変更しない。
   - AccountIdあり: 補正対象として保持する。
6. AccountId検証を全件完了した後、有効対象CaseのPriorityを`High`へ変更する。

AccountId不足の完全なメッセージは`AccountId is required when changing Status to Escalated.`。レコードへ設定するため期待StatusCodeは`FIELD_CUSTOM_VALIDATION_EXCEPTION`、fieldsは空。before API自身はSOQL・DMLを行わず、受け取った`Trigger.new`由来のCase参照を直接変更する。

### 8.6 after API処理順

1. `validateCaseUpdateInputs()`で全構造を検証する。
2. new Listが空なら正常終了する。
3. `selectCasesTransitioningToEscalated()`で対象を抽出する。
4. 対象が空なら正常終了する。
5. 対象CaseすべてのAccountIdを確認する。
   - AccountIdなし: before側と同じ`addError()`を設定し、Task対象から除外する。
   - AccountIdあり: Task作成対象として保持する。
6. AccountId検証を全件完了した後、有効対象CaseからTaskを生成する。
7. Task Listが空ならDMLなしで正常終了する。
8. ループ外でTaskを1回だけ一括insertする。

after側のAccountId検証は、Service直接呼出し等を考慮した防御契約。通常Trigger経路ではbefore側の`addError()`により無効Caseは保存されず、after側へ到達しない。

### 8.7 TaskとDML契約

| 項目 | 最終仕様 |
| --- | --- |
| `WhatId` | 対象CaseのId |
| `OwnerId` | 対象CaseのOwnerId |
| `Subject` | `Review escalated case` |
| DML | `Database.insert`をループ外で最大1回 |
| all-or-nothing | `true` |
| access level | 明示的な`SYSTEM_MODE` |
| DML失敗 | catchせず`DmlException`を伝播。生成対象へ確定したTask群を全件ロールバック |

Taskを引数として受け取らず、固定した3項目だけをCaseから生成する。system modeは、Caseエスカレーションに必須の自動処理を実行ユーザーのTask Create CRUD・FLSへ依存させないため。クラスは`with sharing`とし、設計上はレコードレベル共有を尊重する。

AccountId検証ではレコード単位の除外を許容するが、生成したTask群のDMLでは部分成功を許容しない。対象3件中index 1だけAccountIdなしなら、index 1へエラーを設定し、index 0・2のTask 2件を1文・2行で保存する。Task DMLの1件が失敗した場合は、生成Task全体を保存0件とする。

Trigger経由ではCase updateとTask insertが同一トランザクションである。Task DML例外をcatchしないため、Taskだけでなく起点のCase updateもロールバックされ、Case DML呼出元ではTrigger境界の外側`DmlException`として観測される。

ServiceをTrigger外から直接呼んだ場合、`addError()`はメモリ上のCaseで`hasErrors()`／`getErrors()`により観測できるが、Case DMLや自動ロールバックは発生しない。直接呼出元がエラーを確認する責務を持つ。

## 9. 関連自動化・再入・非機能要件

### 9.1 after-save Flow最終契約

| 項目 | 最終仕様 |
| --- | --- |
| Label | `Case - Set Flow Updated Description` |
| API名 | `Case_Set_Flow_Updated_Description` |
| 対象 | Case |
| 起動 | update時のみ |
| タイミング | after-save |
| 開始条件 | Status=`Escalated`かつDescriptionがnull |
| 条件評価 | 更新のたびに条件を満たせば実行 |
| 更新対象 | トリガしたCase自身 |
| 更新内容 | Description=`Flow Updated` |
| 再入停止 | 再評価時はDescriptionがnullでないため条件不成立 |
| メタデータ | Active状態でGit管理・デプロイ |

Flow再入テスト以外はDescriptionへ値を設定して隔離する。Status条件により、Escalationと無関係なDescription空欄Caseへの副作用を防ぐ。

### 9.2 再入・重複防止

- 初回のbefore／after updateでは非Escalated→Escalatedなので対象となる。
- Flow再入時はold／new StatusがどちらもEscalatedとなるため対象外。Priority再補正とTask重複作成を行わない。
- `CaseTriggerHandler`へloop上限を設定せず、正常なbefore／afterとFlow再入を単純な回数だけで異常再帰と判定しない。
- bypassはテスト準備でのみ使用し、本番の重複防止には使わない。`finally`で解除する。
- 同一トランザクション内で別自動化が`Escalated → Working → Escalated`と往復させる場合、2回目の処理は防げない。この抑制は今回の責務外とし、自動化間の業務ルールと実行順序を見直す。

### 9.3 バルク・ガバナ・セキュリティ

| 項目 | 最終仕様 |
| --- | --- |
| 想定最大入力・対象 | Case 200件 |
| 計算量・追加ヒープ | `O(n)`。対象Case参照Listと最大200件のTask Listが主 |
| SOQL | 0回 |
| before内部DML | 0文・0行 |
| 200件全対象のafter内部 | Task DML 1文・200行 |
| 基本トランザクション全体 | Case updateとTask insertで2文・400行。他の自動化は別途加算 |
| 150件対象・50件対象外 | Task DML 1文・150行、Task 150件 |
| 共有する制限 | 同一同期トランザクション内のSOQL、取得行数、DML文・行、CPU、ヒープをTrigger、Flow、入力規則、他Handlerと共有 |
| sharing | 3 Apexクラスは`with sharing`、Triggerにはsharing宣言なし |
| Task DML権限 | 明示的SYSTEM_MODE。Task Create CRUD・FLSは適用しない |
| 200件超 | Data Loader、Batch Apex等の呼出し・バッチ管理層が分割、進捗、再試行を担当 |

CPUは対象抽出、入力検証、Priority補正、Task生成に加え、Task DMLから起動する他のTrigger・Flowの影響を受ける。各ガバナ制限は「まとめて一つの上限」ではなく、それぞれ独立した上限として同一トランザクション内で共有する。

参照:

- Salesforce Developers「Secure Apex Classes」: https://developer.salesforce.com/docs/platform/lwc/guide/apex-security
- Salesforce Developers「WITH」: https://developer.salesforce.com/docs/platform/salesforce-soql-sosl/guide/sforce-api-calls-soql-select-with.html

## 10. テスト最終設計

### 10.1 共通TriggerHandler

- テストクラス名: `TriggerHandlerTest`

| テストメソッド | 証明すること |
| --- | --- |
| `run_beforeInsert_callsBeforeInsert` | before insertから`beforeInsert()`だけが呼ばれる |
| `run_afterInsert_callsAfterInsert` | after insertから`afterInsert()`だけが呼ばれる |
| `run_beforeUpdate_callsBeforeUpdate` | before updateから`beforeUpdate()`だけが呼ばれる |
| `run_afterUpdate_callsAfterUpdate` | after updateから`afterUpdate()`だけが呼ばれる |
| `run_beforeDelete_callsBeforeDelete` | before deleteから`beforeDelete()`だけが呼ばれる |
| `run_afterDelete_callsAfterDelete` | after deleteから`afterDelete()`だけが呼ばれる |
| `run_afterUndelete_callsAfterUndelete` | after undeleteから`afterUndelete()`だけが呼ばれる |
| `run_outsideTrigger_throwsException` | Trigger context外の`run()`が共通Handler例外を送出する |
| `run_whenBypassed_skipsExecution` | bypass中はcontextメソッドを実行しない |
| `run_afterClearBypass_executes` | `clearBypass()`後はcontextメソッドを再び実行する |
| `bypass_isSeparateForEachHandler` | あるHandlerのbypassが別Handlerへ影響しない |
| `run_withinLoopLimit_executes` | 最大回数以内なら実行できる |
| `run_overLoopLimit_throwsException` | 最大回数を超えると共通Handler例外を送出する |
| `loopCount_isSeparateForEachHandler` | 実行回数をHandler名ごとに個別管理する |

共通Handlerテストの追加方針:

- テストからcontextを明示的に指定できるテスト境界を共通Handlerへ設ける。実Triggerを7種類用意せず、単体テストを容易にするため。
- `TriggerHandler`を継承するテスト用Handlerで7フックをoverrideし、呼び出されたフックのカウンタを増やす。
- Handler名単位のbypass・loop count分離を確認するため、異なる2種類の派生Handlerを用意する。
- bypassは`finally`で解除する。
- loop countはテスト後に同じHandlerの`clearMaxLoopCount()`を呼び、count／Map entryを削除せず上限を無効化する。
- `run_beforeInsert_callsBeforeInsert`では`beforeInsertCalls=1`、他6フックをすべて0とする。
- `run_whenBypassed_skipsExecution`では7フックすべて0、実行中の`isBypassed`をtrue、解除後をfalseとする。
- `run_overLoopLimit_throwsException`では最大回数を1とし、1回目に`beforeInsertCalls=1`、2回目は`TriggerHandler.TriggerHandlerException`となり、`beforeInsertCalls=1`のまま、他6フックを0とする。Handler名を含む完全な例外メッセージはAPI 67.0実測で確定する。

共通Handlerテスト境界の追加確定事項:

- context指定メソッドは`@TestVisible private setTriggerContextForTest`とし、文字列でなく`TriggerContext` enumを受け取ってタイプミスを防ぐ。
- テスト用派生Handlerは`RecordingTriggerHandler`と`SecondaryRecordingTriggerHandler`。前者は7イベントの振分け観測、後者はbypass・loop countのHandler別分離確認に使う。
- loop countの後始末には既存の`clearMaxLoopCount()`を使用して上限を無効化する。count／Map entryの削除用APIを本番クラスへ追加しない。
- `run_overLoopLimit_throwsException`の最大回数は1。期待メッセージ案は`Maximum loop count of 1 reached in RecordingTriggerHandler`。派生Handlerの配置による実際のHandler名表現を確認して確定する。
- `run_outsideTrigger_throwsException`の期待例外は`TriggerHandler.TriggerHandlerException`、完全なメッセージは`Trigger handler called outside of Trigger execution`。
- API 67.0実測事項: loop上限メッセージ中の正確なHandler名。

テスト用状態・配置の追加回答:

- `setTriggerContextForTest`では`isTriggerExecuting=true`とする。
- `context=BEFORE_UPDATE`は例示であり固定値ではない。引数として受け取った`TriggerContext` enum値をそのままcontextへ設定する。
- `RecordingTriggerHandler`と`SecondaryRecordingTriggerHandler`は`TriggerHandlerTest`の内側クラスとし、テスト専用トップレベルクラスを増やさない。
- 内側クラスの`getHandlerName()`文字列表現とloop上限例外の完全なメッセージは、API 67.0で実測して最終確定する。

bypassテストの具体的契約:

- `run_afterClearBypass_executes`は`AFTER_UPDATE`を指定する。`RecordingTriggerHandler`をbypassし、`isBypassed=true`を確認した後に解除して`false`を確認し、`run()`後は`afterUpdateCalls=1`、他6フック=0とする。途中失敗時のstatic状態を残さないため、明示解除に加えて`finally`でも同じHandlerのbypass解除を保証する。
- `bypass_isSeparateForEachHandler`は両Handlerへ`BEFORE_UPDATE`を指定し、`RecordingTriggerHandler`だけをbypassする。`RecordingTriggerHandler`の`isBypassed=true`、`SecondaryRecordingTriggerHandler`はfalseとし、両方を1回ずつ`run()`した後は前者の7フック=0、後者の`beforeUpdateCalls=1`・他6フック=0とする。`finally`で`RecordingTriggerHandler`のbypassを解除する。

loop countテストの具体的契約:

- `run_withinLoopLimit_executes`は`BEFORE_UPDATE`、最大回数2、`run()`2回とする。例外はなく、`beforeUpdateCalls=2`、他6フック=0。`finally`で同じHandlerの`clearMaxLoopCount()`を呼ぶ。
- `loopCount_isSeparateForEachHandler`は両Handlerを`BEFORE_UPDATE`、最大回数1とする。`RecordingTriggerHandler`は1回目成功・2回目上限超過、`SecondaryRecordingTriggerHandler`も1回目成功・2回目上限超過とする。両方とも最終的に`beforeUpdateCalls=1`、他6フック=0となり、一方の上限到達が他方の初回実行へ影響しないことを確認する。`finally`で両Handlerの`clearMaxLoopCount()`を呼ぶ。

共通`TriggerHandler`のテスト設計は、7イベントdispatch、Trigger外実行、bypassと解除・Handler別分離、loop上限内・超過・Handler別分離、テスト用context境界、フック観測、static状態の後始末まで確定した。内側クラスの正確なHandler名と例外メッセージだけはAPI 67.0実測で最終確定する。

### 10.2 CaseEscalationService

- テストクラス名: `CaseEscalationServiceTest`

責務変更後のService直接テスト一覧（2026-09-26）:

before側`validateAndSetPriorityForEscalations`:

1. `validateAndSetPriorityForEscalations_singleTransition_setsPriorityHigh`
2. `validateAndSetPriorityForEscalations_multipleTransitions_setsAllPrioritiesHigh`
3. `validateAndSetPriorityForEscalations_twoHundredTransitions_setsAllPrioritiesHigh`
4. `validateAndSetPriorityForEscalations_nonTargetTransitions_doesNotChangePriority`
5. `validateAndSetPriorityForEscalations_missingAccount_addsErrorAndPreservesPriority`
6. `validateAndSetPriorityForEscalations_validAndMissingAccounts_processesEachCase`
7. `validateAndSetPriorityForEscalations_nullNewCases_throwsIllegalArgumentException`
8. `validateAndSetPriorityForEscalations_nullOldCasesById_throwsIllegalArgumentException`
9. `validateAndSetPriorityForEscalations_emptyNewCases_returnsWithoutChanges`
10. `validateAndSetPriorityForEscalations_containingNullCase_throwsBeforeModification`
11. `validateAndSetPriorityForEscalations_caseWithoutId_throwsIllegalArgumentException`
12. `validateAndSetPriorityForEscalations_oldMapMissingCaseId_throwsIllegalArgumentException`
13. `validateAndSetPriorityForEscalations_oldMapContainingNullValue_throwsIllegalArgumentException`

after側`createReviewTasksForEscalations`:

1. `createReviewTasksForEscalations_singleTransition_createsReviewTask`
2. `createReviewTasksForEscalations_twoHundredTransitions_createsAllTasksInOneDml`
3. `createReviewTasksForEscalations_nonTargetTransitions_doesNotCreateTasks`
4. `createReviewTasksForEscalations_missingAccount_addsErrorWithoutDml`
5. `createReviewTasksForEscalations_validAndMissingAccounts_createsTasksForValidCases`
6. `createReviewTasksForEscalations_taskInsertFailure_rollsBackAllTasks`
7. `createReviewTasksForEscalations_nullNewCases_throwsIllegalArgumentException`
8. `createReviewTasksForEscalations_nullOldCasesById_throwsIllegalArgumentException`
9. `createReviewTasksForEscalations_emptyNewCases_returnsWithoutDml`

共通構造検証helperの全エラー分岐はbefore側で網羅する。after側ではnew List null、old Map null、空Listを確認し、両publicメソッドが同じhelperを呼ぶことを代表的に証明する。private helperの同一実装を両側で重複テストしない理由による。

従来のServiceテスト一覧と具体的Assertは履歴として残すが、メソッド名、引数、Status判定の所在が変わったため、そのままの実装契約には使用しない。新一覧22件について、既存の業務結果Assertを再利用しつつ、new Case Listとold Case Mapの具体データ、構造エラー、AccountId部分成功を追加確定する。

構造入力10テストの具体的契約（2026-09-27）:

- 準備DMLは`Test.startTest()`前に完了し、Service呼出し前後のDML文・行差分を測定する。10件すべてService起因DML 0文・0行、対象Subject／Case Idで検索するTask保存0件。
- 共通の有効データは、保存済みIdを持つnew Case A（old New、新Escalated、Priority Low、有効Account）とnew Case B（old Working、新Escalated、Priority Medium、有効Account）。old／newは同じIdを持つ別のSObject状態として用意する。

before側:

| テスト | 入力 | 期待 |
| --- | --- | --- |
| `...nullNewCases...` | new=null、old Mapにold A | `IllegalArgumentException`、`New Case list must not be null.`。old AはLow・errorsなし |
| `...nullOldCasesById...` | new空List、old=null | `IllegalArgumentException`、`Old Case map must not be null.`。空判定よりMap nullを優先 |
| `...emptyNewCases...` | new空List、old空Map | 例外なし・早期return |
| `...containingNullCase...` | new=[new A, null, new B]、old Mapにold A／B | `IllegalArgumentException`、`New Case must not be null. inputIndex=1`。AはLow、BはMedium、両方errorsなし |
| `...caseWithoutId...` | new=[Id null・Escalated・Low・有効Account]、old空Map | `IllegalArgumentException`、`New Case Id must not be null. inputIndex=0`。Map検索前に失敗しPriority・errors不変 |
| `...oldMapMissingCaseId...` | new=[new A]、old空Map | `IllegalArgumentException`、`Old Case map does not contain the new Case Id. inputIndex=0, caseId={実Id}`。Priority Low・errorsなし |
| `...oldMapContainingNullValue...` | new=[new A]、old MapはA Id=>null | `IllegalArgumentException`、`Old Case must not be null. inputIndex=0, caseId={実Id}`。`containsKey(A Id)=true`、Priority Low・errorsなし |

after側:

| テスト | 入力 | 期待 |
| --- | --- | --- |
| `...nullNewCases...` | new=null、old Mapにold A | `IllegalArgumentException`、`New Case list must not be null.`。old AはLow・errorsなし |
| `...nullOldCasesById...` | new空List、old=null | `IllegalArgumentException`、`Old Case map must not be null.`。空判定よりMap nullを優先 |
| `...emptyNewCases...` | new空List、old空Map | 例外なし・早期return・Task DMLなし |

動的Idを含む2メッセージは実際のCase Idを連結して完全一致させる。構造検証が全件完了するまでPriority補正、`addError()`、Task生成を開始しないことを、入力CaseのPriority・`hasErrors()`不変で証明する。

before側業務6テストの具体的契約（2026-09-27）:

- 準備用Account／Caseのinsertは`Test.startTest()`前に完了し、Service呼出し前後でDML文・行差分を測定する。6件すべて0文・0行。
- AccountId欠如時の完全なエラーメッセージは`AccountId is required when changing Status to Escalated.`。レコード単位の`addError()`であり、Serviceメソッド自体は例外を送出しない。

| テスト | new／oldと入力順 | 期待 |
| --- | --- | --- |
| `...singleTransition...` | 0: New→Escalated、有効Account、Low | High、errors 0 |
| `...multipleTransitions...` | 0: New→Escalated／Low、1: Working→Escalated／Medium、2: New→Escalated／Low。すべて有効Account | 3件ともHigh・errors 0。入力Listの件数・順序不変 |
| `...twoHundredTransitions...` | 200件すべてNew→Escalated、有効Account、Low。new Case Idとold Mapを1対1対応 | 全200件High・errors 0。ループで全件確認 |
| `...nonTargetTransitions...` | 0: New→Working／Low、1: Escalated→Escalated／Medium、2: Escalated→Working／Low。すべて有効Account | PriorityはLow／Medium／Lowのまま、全件errors 0 |
| `...missingAccount...` | 0: New→Escalated、AccountId null、Low | Lowを維持、errors 1、`FIELD_CUSTOM_VALIDATION_EXCEPTION`、fields空、完全なmessage一致 |
| `...validAndMissingAccounts...` | 0: New→Escalated・有効Account・Low、1: Working→Escalated・AccountId null・Medium、2: New→Working・AccountId null・Low | 0はHigh・errors 0、1はMedium維持・上記error 1、2はLow・errors 0。対象外CaseにはAccountId検証を行わない |

Priority補正と`addError()`はStatus遷移対象だけに適用する。混在テストのindex 2はAccountIdをnullにしてもエラーなしとし、対象抽出がAccountId検証に先行することを証明する。

after側業務6テストの具体的契約（2026-09-27）:

- 準備DMLは計測前に完了する。Taskは`WhatId=対象Case.Id`、`OwnerId=対象Case.OwnerId`、`Subject='Review escalated case'`とし、ループ外で`allOrNothing=true`、明示的な`SYSTEM_MODE`により一括insertする。

| テスト | new／oldと入力順 | Task・エラー・DMLの期待 |
| --- | --- | --- |
| `...singleTransition...` | 0: New→Escalated、有効Account、実行ユーザーOwner | Task 1件、共通3項目一致、errors 0、DML 1文・1行、保存1件 |
| `...twoHundredTransitions...` | 200件すべてNew→Escalated、有効Account、実行ユーザーOwner | Task 200件、DML 1文・200行。WhatId別Mapは200キー・各1件で、全OwnerId／Subject一致 |
| `...nonTargetTransitions...` | 0: New→Working・AccountId null、1: Escalated→Escalated・AccountId null、2: Escalated→Working・有効Account | 全件errors 0、Task 0件、DML 0文・0行。対象抽出をAccountId検証より先に行う |
| `...missingAccount...` | 0: New→Escalated、AccountId null、実行ユーザーOwner | Task 0件、DML 0文・0行、例外なし。error 1、`FIELD_CUSTOM_VALIDATION_EXCEPTION`、fields空、AccountId不足message完全一致 |
| `...validAndMissingAccounts...` | 0: New→Escalated・有効Account、1: Working→Escalated・AccountId null | 0だけTask 1件、1だけAccountId不足error 1。DML 1文・1行、保存1件、例外なし |
| `...taskInsertFailure...` | 0: New→Escalated・有効Account・User Owner、1: Working→Escalated・有効Account・メモリ上だけOwnerIdをAccount Idへ変更 | 両Case errors 0。Task DML 1文・2行で`DmlException`、all-or-nothingにより両Taskとも保存0件 |

Task失敗テストのAPI 67.0実測契約は、`getDmlIndex(0)=1`、`getDmlType(0)=FIELD_INTEGRITY_EXCEPTION`、fields 1件=`OwnerId`、`getDmlId(0)=null`とする。messageは完全一致せず、非blankかつ設定したAccount Idを含むことを確認する。OwnerId項目の特定は`getDmlFieldNames()`、実際の不正値はmessageで証明する。人間向けmessageの文言は組織差があるため、`id value of incorrect type`は必須条件にしない。DML差分は1文・2行、対象Case Idと固定Subjectで検索したTaskは0件とする。`getDmlStatusCode()`は使用せず、`System.StatusCode`を返す`getDmlType()`を使用する。直接Service呼出しで付けた`addError()`はメモリ上のCaseへ設定され、この呼出し自体ではCase DMLやロールバックを発生させない。

公式根拠: Salesforce Apex Reference Guide「DMLException and EmailException Methods」: https://resources.docs.salesforce.com/latest/latest/en-us/sfdc/pdf/salesforce_apex_reference_guide.pdf

### 10.3 CaseTrigger／CaseTriggerHandler統合

- テストクラス名: `CaseTriggerHandlerTest`
- 薄い`CaseTrigger`の実イベント発火と、`CaseTriggerHandler`からServiceまでをDML経由で統合検証する。

| テストメソッド | 証明すること |
| --- | --- |
| `update_nonEscalatedToEscalated_setsPriorityAndCreatesTask` | AccountIdありCaseの`New → Escalated`でPriority High、Task 1件、WhatId・OwnerId・Subject一致 |
| `update_twoHundredCasesToEscalated_processesAllRecords` | 200件一括で全Case Escalated・High、Task 200件、Caseごとに1件 |
| `update_toEscalatedWithoutAccount_failsWithAddError` | AccountIdなしCaseの更新失敗、DB Status・Priority維持、Task 0件 |
| `update_validAndInvalidCasesWithPartialSuccess_savesOnlyValidCase` | `Database.update(..., false)`で有効Caseだけ保存、無効CaseはSaveResult失敗、有効CaseのTaskだけ作成 |
| `update_nonTargetStatusTransition_doesNotRunEscalationProcessing` | Escalated以外への遷移でPriority・Task処理なし |
| `update_alreadyEscalatedCase_doesNotCreateAnotherTask` | Escalatedのまま別項目更新してもPriority再補正・Task追加なし |
| `insert_withEscalatedStatus_doesNotRunUpdateProcessing` | Escalatedでinsertしてもbefore／after update処理なし |
| `update_withFlowReentry_createsOnlyOneTask` | Description空のCaseをEscalatedへ更新し、Flowが`Flow Updated`へ再更新してもTask 1件のみ |
| `update_whenTaskInsertFails_rollsBackCaseAndTasks` | after updateのTask一括insert失敗でCase更新・Tasksを全ロールバックし、呼出元が外側`DmlException`を受け取る |
| `update_whenHandlerBypassed_skipsProcessingAndClearsBypass` | Handler bypass中はPriority・Task処理なし、`finally`解除後`isBypassed=false` |

Trigger統合経路のTask失敗データ:

- `CaseEscalationService`に`@TestVisible private static Id reviewTaskOwnerIdOverride`を設け、通常時はnullのままとする。
- 統合テスト時だけ、準備Account Idを`reviewTaskOwnerIdOverride`へ設定する。Serviceはこの値をTask.OwnerIdへ設定し、Taskが参照できないAccount IdによってTask insertを失敗させる。
- テストは`finally`で`reviewTaskOwnerIdOverride`をnullへ戻し、後続テストへstatic状態を残さない。通常実行では従来どおりCase.OwnerIdをTask.OwnerIdへ設定するため、本番契約は変更しない。
- API 67.0実測では、Case専用Queue IdをTask.OwnerIdへ設定してもTaskが正常作成されたため、Queueを使った失敗データは採用しない。
- Task DML失敗時はCase更新を含むトランザクション全体をロールバックし、CaseのStatus・Priorityは更新前の値、Task件数は0とする。

`update_whenTaskInsertFails_rollsBackCaseAndTasks`の完全な契約:

- 更新前CaseはStatus=`New`、Priority=`Low`、Description=`Test Description`、有効なAccountId、OwnerId=`UserInfo.getUserId()`。
- 発火直前はStatusだけを`Escalated`へ変更し、Priorityは`Low`のままとする。
- 通常の`update`で発火し、外側`DmlException`の暫定期待は`getNumDml()=1`、`getDmlIndex(0)=0`、`getDmlType(0)=StatusCode.CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY`、`getDmlId(0)=Case.Id`。
- 外側messageは完全一致せず、CaseTrigger、after update、内部Task insert失敗、`FIELD_INTEGRITY_EXCEPTION`、不正値として設定したAccount Idを確認する。
- API 67.0実測では、外側StatusCodeは`CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY`、外側message内のTask失敗は`FIELD_INTEGRITY_EXCEPTION`となる。
- catch後は必ずSOQLでCaseを再取得し、Status=`New`、Priority=`Low`、Description=`Test Description`を確認する。メモリ上のCase値はロールバック証拠に使わない。
- TaskはWhatId=Case IdかつSubject=`Review escalated case`で0件。
- Account、Caseの準備完了後に計測する。API 67.0実測では、ロールバックされたTrigger内部のTask insertは呼出元から取得したDML差分に残らず、外側Case updateの1文・1行となる。beforeのPriority直接代入は追加DMLなし。

正常統合テストの具体的契約:

- `update_nonEscalatedToEscalated_setsPriorityAndCreatesTask`:
  - 準備CaseはStatus=`New`、Priority=`Low`、Description=`Test Description`、準備Account Id、OwnerId=`UserInfo.getUserId()`、Origin=`Phone`、Subject=`Single Escalation Test`。
  - Account 1件とCase 1件を`Test.startTest()`前にinsertし、Statusだけを`Escalated`へupdateする。
  - DB再取得後はEscalated、High、Description／AccountId／OwnerId維持。
  - Taskは1件、WhatId=Case Id、OwnerId=Case OwnerId、Subject=`Review escalated case`。
- `update_twoHundredCasesToEscalated_processesAllRecords`:
  - 同じAccount Id、current User OwnerId、New、Low、`Test Description`、Phoneを持つCase 200件を用意し、Subjectは`Bulk Escalation Test 0`〜`199`。
  - Account 1件とCase 200件を`Test.startTest()`前に一括insertし、全件のStatusだけをEscalatedへ一括updateする。
  - DB再取得後は全件Escalated、High、Description／AccountId／OwnerId維持。
  - Task総数200、WhatId種類数200、各WhatIdのTask 1件、OwnerIdは対応Caseと一致、Subjectは全件固定値。
- 両テストともDescriptionが非nullのためFlow開始条件を満たさない。
- 正常1件はCase update 1文・1行とTask insert 1文・1行で、DML差分2文・2行。
- 正常200件はCase update 1文・200行とTask insert 1文・200行で、DML差分2文・400行。

AccountIdなし・部分成功統合テストの具体的契約:

- `update_toEscalatedWithoutAccount_failsWithAddError`:
  - 初期値はStatus=`New`、Priority=`Low`、Description=`Test Description`、AccountId=null。
  - StatusだけEscalatedへ変更し、通常の`update`で発火する。
  - 外側`DmlException`は`getNumDml()=1`、`getDmlIndex(0)=0`、`getDmlType(0)=StatusCode.FIELD_CUSTOM_VALIDATION_EXCEPTION`、`getDmlMessage(0)=AccountId is required when changing Status to Escalated.`。
  - DB再取得後はNew・Low、Task 0件。DML差分1文・1行。
- `update_validAndInvalidCasesWithPartialSuccess_savesOnlyValidCase`:
  - index 0は有効AccountId、index 1はAccountId=null。どちらもNew、Low、`Test Description`。
  - 両方のStatusをEscalatedへ変え、`Database.update(cases, false)`で発火する。
  - `SaveResult[0]`はsuccess、Id=有効Case Id、errors 0。`SaveResult[1]`はfailureだがupdate対象は既存レコードのためId=無効Case Id、errors 1、StatusCode=`FIELD_CUSTOM_VALIDATION_EXCEPTION`、完全なaddErrorメッセージ。
  - DB再取得後は有効CaseがEscalated・High、無効CaseがNew・Low。
  - Taskは1件で、有効Case Id・有効Case OwnerId・固定Subjectに一致。DML差分2文・3行。
- 両テストともDescription非nullでFlowを起動しない。

対象外統合テストの具体的契約:

- 3テストとも有効なAccountIdを設定し、AccountId不足ではなくStatus遷移またはTriggerイベントが対象外理由であることを分離して確認する。
- `update_nonTargetStatusTransition_doesNotRunEscalationProcessing`:
  - 準備CaseはStatus=`New`、Priority=`Low`、Description=`Test Description`、有効なAccountId、current User OwnerId、Origin=`Phone`、Subject=`Non Target Transition Test`。
  - Statusだけを`Working`へ変更して通常updateする。
  - DB再取得後はWorking、Low、`Test Description`。Taskは0件、DML差分1文・1行。
  - FlowはStatusがEscalatedでなくDescriptionも非nullのため開始条件を満たさない。
- `update_alreadyEscalatedCase_doesNotCreateAnotherTask`:
  - Escalated、Low、`Test Description`、有効なAccountId、current User OwnerId、Phone、Subject=`Already Escalated Test`で直接insertする。insert後のTask 0件も確認する。
  - Subjectだけを`Already Escalated Test Updated`へ変更して通常updateする。old／new StatusはいずれもEscalatedで遷移条件はfalse。
  - DB再取得後はEscalated、Low、`Test Description`、更新後Subject。Taskは0件、準備完了後のDML差分1文・1行。
  - FlowはDescription非nullのため開始条件を満たさない。
- `insert_withEscalatedStatus_doesNotRunUpdateProcessing`:
  - Accountだけを事前作成し、Escalated、Low、`Test Description`、有効なAccountId、current User OwnerId、Phone、Subject=`Escalated Insert Test`のCaseを検証対象DMLでinsertする。
  - DB再取得後はEscalated、Low、`Test Description`。Taskは0件、DML差分1文・1行。
  - Case Triggerはupdateイベントだけを対象とし、Flowもupdate-onlyである。加えてDescription非nullのため、Flowによる追加updateはない。

Flow再入統合テストの具体的契約:

- `update_withFlowReentry_createsOnlyOneTask`:
  - 準備CaseはStatus=`New`、Priority=`Low`、Description=null、有効なAccountId、current User OwnerId、Origin=`Phone`、Subject=`Flow Reentry Test`。
  - AccountとCaseを事前insertし、StatusだけEscalatedへ通常updateする。
  - 初回before／after updateではold New・new Escalatedで遷移条件がtrueとなり、PriorityをHighへ補正してTaskを1件作成する。
  - after-save FlowがDescriptionを`Flow Updated`へ変更して同じCaseを再更新する。再入before／after updateではold／new StatusがともにEscalatedで遷移条件はfalseとなり、Priority再補正とTask追加を行わない。
  - Handlerの`run()`は、初回before、初回after、Flow再入before、Flow再入afterの合計4回。再入に対応する3回目・4回目が遷移条件falseである。
  - DB再取得後はEscalated、High、Description=`Flow Updated`。Description完全一致でFlow実行を確認する。
  - Case Idと固定Subjectで取得するTaskは厳密に1件で、WhatId、OwnerId、Subjectも一致させる。
  - 暫定DML差分は、最初のCase update、Task insert、FlowのCase updateを合わせて3文・3行。API 67.0実測で確定する。
  - Flowの再評価時はDescriptionがnullでないため開始条件を満たさず終了する。

bypass統合テストの具体的契約:

- `update_whenHandlerBypassed_skipsProcessingAndClearsBypass`:
  - 準備CaseはStatus=`New`、Priority=`Low`、Description=`Test Description`、有効なAccountId、current User OwnerId、Origin=`Phone`、Subject=`Handler Bypass Test`。
  - 暫定Handler名は`CaseTriggerHandler`とし、API 67.0で`getHandlerName()`の実測値を確認する。
  - bypass中にStatusだけEscalatedへ通常updateする。DB再取得後はEscalated、Low、`Test Description`、Task 0件、DML差分1文・1行。
  - Description非nullによりFlowを隔離し、Flow updateは0文・0行とする。
  - `try`内でbypass登録、`isBypassed(...) == true`のAssert、Case updateを順に行う。
  - `finally`で必ず`clearBypass(...)`を呼び、`try`／`finally`完了後に`isBypassed(...) == false`を確認する。

Flow採用判断:

- 実FlowをCP4要件へ追加する。理由は、Apex単独の2回目updateではなく、after-save Flowによる同一トランザクション再入を実際に学習・検証するため。
- テストだけの隠れた補助Flowにはせず、DXメタデータ、詳細設計、Git、デプロイ、統合テストの証拠対象とする。
- Apex Recipesの参照スナップショットには同じFlowが存在しないため、これは本人が選択したCP4独自の学習要件として区別する。

Flow契約の本人回答:

| 項目 | 設計 |
| --- | --- |
| 対象 | Case |
| 起動 | 更新時のみ |
| タイミング | after-save |
| Label | `Case - Set Flow Updated Description` |
| API名 | `Case_Set_Flow_Updated_Description` |
| 開始条件 | Description `Is Null = true`かつStatus=`Escalated` |
| 条件評価 | 更新のたびに条件を満たせば実行 |
| 更新対象 | トリガしたCase自身 |
| 更新内容 | Description=`Flow Updated` |
| 再入停止 | 2回目はDescriptionがnullでないため開始条件を満たさない |
| 他テスト隔離 | Flow再入テスト以外ではDescriptionへ値を設定しておく |
| メタデータ | Active状態でGit管理・デプロイ |

Status条件を加える理由は、Escalationと無関係なDescription空欄CaseまでFlowが更新することを防ぎ、副作用を要件範囲へ限定するため。Flow契約は確定。

## 11. 代替設計比較と責務境界

本人が説明済みの採用判断:

| 比較 | 採用案 | 採用理由 | 認識している短所・リスク |
| --- | --- | --- | --- |
| 共通Handler／Case専用直接dispatch | 共通`TriggerHandler` | 共通Handlerを学習するため | Case Triggerしかない段階では共通化コストが過大になり得る |
| before補正／afterでCase再更新 | before updateで直接補正 | 追加DMLなしで値を変更できる | 他のTrigger／FlowもPriorityを変更する場合は処理順・競合を考慮する必要があり、戻り値がないため補正件数や失敗内容を結果として受け取れない |
| 同期／非同期、生成Taskの全件成功／DML部分成功 | Taskを同期作成し、生成対象へ確定したTask群は全件成功必須 | 保存可能なEscalated Caseへ同一トランザクションでTaskを作り、Task DMLの一部失敗を残さない | AccountId検証では欠如Caseをレコード単位で除外するため、Service直接入力全体ではTaskなしCaseを許容する。Task 1件のDML失敗では生成対象Task群とCase更新が全件エラーになる |
| system／user mode | Task DMLをsystem mode | 実行ユーザーの権限にかかわらず業務上必要なTaskを作る | 権限のない項目まで不必要に設定する危険がある |
| 実Flow／テスト内の直接再更新 | 実際のafter-save Flow | 直接updateではFlow統合テストの代替にならない | Flow自体のテストが必要で、障害時はApexとFlowの両方を調査する |
| Status遷移／loop count・処理済みId | Status遷移条件 | loop countは後続処理で回数が変わり設定が難しい | 同一トランザクション内でStatusが往復すると再度対象になり得る |
| `void`変更／結果を返す方式 | 引数Caseを補正する`void`方式 | 戻り値を受け取り再反映する処理が不要 | 引数を変更するため、呼出元がメソッド名と契約を理解する必要がある |

Gate C／D実測事項: API 67.0固有の例外型、StatusCode、DML計測値、Handler名を実装・実測で確定する。

本人が説明した不採用理由:

- Task DMLをuser modeにすると、実行ユーザーのTask権限不足でCase更新全体が失敗し、必須業務自動化の要件を満たさないため採用しない。
- TaskをQueueable等で非同期作成するとCase更新とTask作成が別トランザクションになり、Case保存成功時点でTask作成を保証できない。後続失敗時にCaseだけEscalatedでTaskがない状態になるため採用しない。
- 生成対象へ確定したTask群のDML部分成功は、一部の保存可能CaseだけTaskがない状態を作るため採用しない。AccountId欠如Caseの事前除外とは区別する。非同期化するなら別途通知・追跡機構が必要になる。
- staticな処理済みCase Idは、beforeでIdを記録するとafterのTask作成まで抑制する危険があり、同一トランザクション内の正当な再エスカレーションまで一律に抑止するため採用しない。
- before updateでは`Trigger.new`のCaseを直接変更すれば追加DMLなしで保存でき、補正済みListとして同じCase参照を返すだけでは冗長になるため、戻り値方式を採用しない。

最終責務境界:

| コンポーネント | 担当すること | 担当しないこと |
| --- | --- | --- |
| `CaseTrigger` | Case Triggerの入口として`CaseTriggerHandler`を生成し、`run()`を呼ぶ | イベント判定 |
| `TriggerHandler` | `Trigger.operationType`に応じたフックへの振り分け、Trigger外実行の検出、Handler単位のbypass、loop count管理 | Case固有条件、SOQL、DML、対象レコード抽出 |
| `CaseTriggerHandler` | `Trigger.new`／`Trigger.oldMap`を取得・保持し、イベントに適したServiceメソッドを呼ぶ | Status遷移判定、AccountId検証、Task生成、Priority直接補正 |
| `CaseEscalationService` | Status新旧比較による対象抽出、before側の入力構造検証、AccountIdなしへの`addError()`、有効CaseのPriority High補正。after側のTask生成とsystem mode・all-or-nothing一括insert | Triggerイベントdispatch、SOQL、Case追加update |
| after-save Flow | 更新後CaseがEscalatedかつDescription nullなら、同じCaseのDescriptionを`Flow Updated`へ更新 | Status遷移判定、Priority補正、AccountId検証、Task作成 |
| 呼出元・バッチ管理層 | Case更新DML、通常DML／`Database.update(..., false)`の選択、200件超の分割、非同期化、バッチ間成功管理、失敗記録・再試行 | Trigger内部の遷移判定、Priority補正、Task生成、イベント振り分け、Service入力処理 |

今回全体の対象外処理:

- `before insert`、`after insert`、`before delete`、`after delete`、`after undelete`。対象イベントは`before update`と`after update`のみ。
- 1回のTrigger実行で200件を超える入力、200件超の分割、複数バッチ全体の全件成功保証、1,000件全体等の一括ロールバック。
- Data Loader／Bulk API全体の進捗管理、バッチ間の成功・失敗集計、失敗記録・再試行。
- Task作成の非同期化と部分成功、別トランザクションのTask成否通知・追跡機構。
- 他の自動化を含めたガバナ残量の事前判定。
- Custom Metadata等による動的Trigger dispatch。CP4は直接dispatchを対象とする。
- Statusを往復させる自動化に対する一律の再エスカレーション抑制。必要時は自動化間の業務ルールと実行順序を見直す。

| Gate B項目 | 判定 |
| --- | --- |
| 7 | 完了。新Service直接テスト22件すべてについて具体的入力・Assert・DML契約を確定 |

Serviceの2つのpublicメソッド、業務条件、Flow、テスト、代替案、責務境界は確定済み。Gate Bは2026-09-27に100%で通過した。API 67.0でのみ確定できる例外メッセージ・inner class名表現・DML実測値はGate C／Dの実測項目として残す。

## 12. 実装・検証状態

- Apex実装: 一部確認済み
  - `TriggerHandler.cls`: 2026-10-02に本人作成内容を静的レビュー。最終設計の主要契約と一致し、機能上の重大指摘なし
  - 本人修正によりstaticコレクションをfield宣言時初期化へ統一し、最終設計との差分を解消
  - `CaseEscalationService.cls`: 2026-10-03に本人作成内容を静的レビュー。2 public API、構造検証、Status遷移、AccountId、Priority、Task、SYSTEM_MODE・all-or-nothingの契約と一致し、機能上の重大指摘なし
  - 本人修正により定数field配置警告を解消し、AccountId検証を`validateAccountIdsAndSelectValidCases`へ共通化。本人説明を確認し、第8.2章の最終helper一覧へ反映済み
  - `CaseTriggerHandler.cls`: 2026-10-04に本人作成内容を静的レビュー。第7章のクラス宣言、2 field、constructor、before／after Service委譲、責務境界と一致し、機能上の指摘なし
  - `CaseTrigger.trigger`: 2026-10-05に本人提出。初回はHandler instanceを生成せずinstance `run()`をstatic contextから呼んでいたが、本人修正後は第6章のTrigger名、Case対象、before／after update、Handler生成・instance `run()`呼出しと一致
- Trigger実装: 確認済み。修正後のCode Analyzerは指摘0件。依存Apex・Flowを含むAPI 67.0チェック専用デプロイは成功
- テスト実装: 一部提出・未完了
  - `TriggerHandlerTest`: 最終設計の14テストメソッドを確認
  - API 67.0で14/14成功、失敗0
  - `TriggerHandler`カバレッジ71.681%で75%未満のため、チェック専用デプロイ全体はFailed
  - 未到達は実Trigger constructorのcontext対応、入力検証分岐、親の既定空hook、loop countの一部API
  - loop上限messageを本番と同じHandler名算出式で期待値化しているため、API 67.0での内側クラス名文字列そのものは未確定
  - `CaseEscalationServiceTest`: 最終設計の22テストメソッドを確認
  - API 67.0で22/22成功、失敗0。Serviceカバレッジ73/74箇所・約98.65%
  - Task DML失敗テストは`FIELD_INTEGRITY_EXCEPTION`、index 1、Id null、fields 1件=`OwnerId`、message非blank、不正Account Idを確認
  - 後続のDML差分1文・2行とall-or-nothingによるTask保存0件も通過
  - `CaseTriggerHandlerTest`: 最終設計の10テストメソッドを確認
  - API 67.0で10/10成功。正常1件・200件、addError、部分成功、対象外、Flow再入、Task失敗ロールバック、bypassを確認
- DXメタデータ: Apexクラス／TriggerのAPI 67.0・Activeを確認。Flow `Case_Set_Flow_Updated_Description`はAPI 67.0、RecordAfterSave、Case Update、Status=`Escalated`かつDescription null、Description=`Flow Updated`、Activeを確認
- 静的解析（Gate C時点）: `TriggerHandler.cls`のみ実施
  - Salesforce Code Analyzer終了コード0
  - Critical 0、High 0、Moderate 8、Low 15、Info 6
  - Moderateはクラス全体のCyclomatic Complexity 41が1件と、既定動作なしという設計上意図した7 hookのEmptyStatementBlock 7件
  - LowはApexDoc、Infoは末尾空白。対処または許容理由の本人判断待ち
- `CaseEscalationService.cls`静的解析:
  - 完全なRecommended実行はGraph Engineの完了結果が返らず、ローカルPMD・Regex・CPDに限定して再実行
  - 初回Moderate 4、Low 3、Info 3から、本人修正後はModerate 2、Low 3、Info 2
  - 定数field配置2件とbefore／afterのAccountId処理重複1件は解消
  - 残るModerateは意図的なprivate constructorの空blockと`validateCaseUpdateInputs`のCyclomatic Complexity 14
  - LowはApexDoc 3件、Infoは末尾空白2件
- `CaseTriggerHandler.cls`静的解析:
  - Salesforce Code Analyzer終了コード0
  - Critical 0、High 0、Moderate 0、Low 2、Info 0
  - Low 2件はクラスとconstructorのApexDoc不足であり、機能契約への影響なし
  - ログ: ローカル一時ファイルとして確認し、公開対象には含めない
- `CaseTriggerHandlerTest.cls`静的解析:
  - Salesforce Code Analyzer終了コード0
  - Critical 0、High 0、Moderate 11、Low 11、Info 0
  - Moderateは本人採用済みunderscoreテスト名10件と4引数Assert helper 1件
  - Lowは権限検証を目的としない統合テストへの`System.runAs`推奨10件とApexDoc 1件
  - ログ: ローカル一時ファイルとして確認し、公開対象には含めない
- コンパイル: 新規スクラッチ組織がActiveであることを確認。`TriggerHandler`単体のAPI 67.0チェック専用デプロイは1/1成功。2026-10-04には`TriggerHandler`、`CaseEscalationService`、`CaseTriggerHandler`の3クラスをまとめたチェック専用デプロイが3/3成功、コンポーネントエラー0
  - 2026-10-05の4コンポーネント確認では依存3クラス成功、`CaseTrigger`だけ失敗。エラーは`Non static method cannot be referenced from a static context: void TriggerHandler.run()`（2行目、24列目）
  - 修正後、依存3クラス、`CaseTrigger`、Flowの5コンポーネント確認は5/5成功、コンポーネントエラー0
- テスト・実デプロイ: 2026-10-06のチェック専用デプロイは8/8コンポーネント成功。`TriggerHandlerTest` 14/14、`CaseEscalationServiceTest` 22/22、`CaseTriggerHandlerTest` 10/10の全46テスト成功、失敗0、カバレッジ警告0。実デプロイは未実施
- Gate C進捗: **100%（6/6）・完了**。共通`TriggerHandler`、`CaseTrigger`、`CaseTriggerHandler`、`CaseEscalationService`、after-save Flow、設計済み全46テスト、本人自己確認を確認済み。2026-10-07にHandler instance呼出しとSYSTEM_MODE／with sharingの説明訂正も完了
- Gate D提出静的解析（2026-10-07）:
  - `evidence/cp4/static-analysis/`へサニタイズ済みJSON／HTMLを保存
  - Code Analyzer全体はCritical 0、High 0、Moderate 71、Low 50、Info 2
  - Flow専用解析はCritical 0、High 1、Moderate 1、Low 2、Info 0
  - Highは`MissingFaultHandler`、Moderateは既知の`SameRecordUpdate`、Lowは`MissingDescription` 2件
  - `SameRecordUpdate`はFlow再入学習の設計判断と一致するが、`MissingFaultHandler`は未解消のため最終静的解析は未通過
  - 本人は対象Flowをテストフローと位置づけ、`MissingFaultHandler`に対する障害パスを追加しない方針を選択。例外受容の最終確定には、適用範囲と失敗時影響の本人説明を要する
  - 2026-10-08、利用範囲はスクラッチ組織等のテスト環境に限定すると本人が確定。障害パスを追加せず次へ進む本人判断により、High 1件を証拠へ残した既知例外として受容。High 0とは評価しない
- デプロイ: 2026-10-08、`checkOnly=false`の実デプロイに成功。8/8コンポーネント成功、エラー0。Salesforce CLIのdeploy reportでも独立確認済み
- Apexテスト: 設計済みテストは実行確認済み。全46/46成功。カバレッジは`CaseTrigger` 1/1、`CaseTriggerHandler` 7/7、`CaseEscalationService` 73/74、`TriggerHandler` 91/113、Flow 1/1要素
- Gate D証拠（2026-10-07）:
  - テスト要約JSONは46/46成功、test run coverage 88%、org-wide coverage 88%を記録
  - Run ID、Deployment ID、実行コマンドを持たないため単独では実行元を追跡できない
  - 実デプロイ結果、High指摘解消、証拠重複整理、Git正本確認が残る
- Gate D実デプロイ証拠（2026-10-08）:
  - `evidence/cp4/tests/cp4-deploy-and-tests-2026-10-08.json`
  - API 67.0、`checkOnly=false`、8/8コンポーネント成功、コンポーネントエラー0
  - 指定3テストクラスの46/46成功、失敗0、Apex coverage 88.32%、Flow 1/1要素
  - Deployment IDを保持し、Salesforce CLI照会結果と一致
  - 3-byte重複ファイル4件は本人が削除。CP4証拠6ファイルの機密・識別情報・ローカル絶対パスマーカー0件を再確認
  - 生成HTMLの末尾空白8件を本人が修正後、staged 25ファイル、cached diff check終了コード0、未ステージ・未追跡0を確認
  - Gate Dは100%（5/5）で通過。本人振り返りも2026-10-08に完了
  - CP4本体・テスト・設計・証拠はcommit `9bd46d7a4511232219aa1cc918be096c1bb7fee1`へ保存し、`origin/feature/cp4-trigger-recipes`へpush済み
  - 本記録の文書commit／push、PR、review、mergeはCP4完了前の残作業

## 13. 設計判断履歴

| 日付 | 判断 | 理由 |
| --- | --- | --- |
| 2026-09-12 | 最小共通`TriggerHandler`を採用 | dispatch、bypass、loop countに未理解部分があり、学習目的で本人実装・テストするため |
| 2026-09-13 | `before update`と`after update`を使用 | Case自身の補正は追加DMLなしで行い、TaskはCase保存成功後の副作用として作成するため |
| 2026-09-14 | Status遷移抽出を個別Handlerの共通privateメソッドへ置く | before／after間の判定重複を避け、対象条件を一箇所で管理するため |
| 2026-09-15 | before Serviceを`public static void validateAndSetPriority(List<Case>)`とする | 状態保持や戻り値を不要とし、Handlerが抽出した`Trigger.new`由来Caseを直接検証・補正するため |
| 2026-09-16 | null入力は`IllegalArgumentException`とし、全件null検証後に業務検証・補正する | 不正なメソッド引数を業務上の`addError()`と区別し、null混在時に一部Caseだけが先に変更される状態を避けるため |
| 2026-09-16 | 対象Listが空ならbefore／afterともHandlerからServiceを呼ばない | 不要なService呼出しとafter側の空Task DMLを避け、対象なしの流れを明示するため |
| 2026-09-16 | Task DMLはall-or-noneの明示的system modeとする | 確認TaskをCaseエスカレーションの必須副作用とし、1件でも失敗したらCase更新を含めて全体を不成立にする初期方針のため |
| 2026-09-16 | Task入力を保存済みCase由来のWhatId・OwnerIdと固定Subjectに限定する | system modeの特権処理へ呼出元が任意のTask項目・値を注入する範囲を狭めるため |
| 2026-09-17 | CaseTriggerHandlerへloop count上限を設定しない | 正常なbefore／afterとFlow再入を単純な実行回数だけでは異常再帰と区別できないため |
| 2026-09-17 | Status往復による再処理は今回の責務外 | Apex側で一律抑制せず、自動化間の業務ルールと実行順序で解決すべき設計問題だから |
