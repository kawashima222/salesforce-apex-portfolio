# CP6 Security Recipes 詳細設計書

## 目次

1. [文書情報](#1-文書情報)
2. [要件](#2-要件)
3. [対象範囲と責務](#3-対象範囲と責務)
4. [AccountQueryService 詳細設計](#4-accountqueryservice-詳細設計)
5. [AccountUpdateService 詳細設計](#5-accountupdateservice-詳細設計)
6. [セキュリティ設計](#6-セキュリティ設計)
7. [テストデータ・権限設計](#7-テストデータ権限設計)
8. [AccountQueryServiceTest 詳細設計](#8-accountqueryservicetest-詳細設計)
9. [AccountUpdateServiceTest 詳細設計](#9-accountupdateservicetest-詳細設計)
10. [ガバナ制限・データ量](#10-ガバナ制限データ量)
11. [設計判断と代替案](#11-設計判断と代替案)
12. [未確定事項・実測事項](#12-未確定事項実測事項)
13. [実装・検証状態](#13-実装検証状態)
14. [設計判断履歴](#14-設計判断履歴)

## 1. 文書情報

| 項目 | 内容 |
| --- | --- |
| 対象CP | CP6 Security Recipes |
| 練習要件 | 実行ユーザーのCRUD・FLS・共有を考慮したAccount参照・更新 |
| 状態 | Gate B 88%（7/8）・項目8は本人実装と並行確定／Gate C本人実装検討開始・未提出 |
| 作成日 | 2026-10-26 |
| 最終更新日 | 2026-10-26 |
| 作業ブランチ | `feature/cp6-security-recipes` |
| 根拠 | `GOAL_SPEC.md`、`PLAN.md`、`LEARNING_PROGRESS.md`、本人によるGate A・Gate B説明 |

この文書は、本人が現時点までに説明して確定した設計を実装契約として整理する。未回答事項をAIが推測で補完せず、`未確定`または`実測待ち`と明記する。

本人の希望により、Gate B項目8の最終クラスAPI、DTO配置、計算量、代替案比較、最終リスクは、Gate Cの本人実装と並行して確定する。したがって、この文書は現段階版であり、実装後に設計と実装を再照合して更新する。

## 2. 要件

### 2.1 Account参照

- 呼出元から渡されたAccount Id集合を条件にAccountを一括検索する。
- 実行ユーザーのAccount CRUD、項目FLS、レコード共有を適用する。
- 権限不足はfail-fastとし、例外を呼出元へ伝播する。
- 共有により参照できないAccountと存在しないAccountは正常な対象外として結果から除外する。
- `Id`、`Name`、`AccountNumber`を取得する。
- `AccountNumber ASC NULLS LAST, Id ASC`で決定的に並べる。
- 入力Setを変更しない。
- SOQLをループ内で実行しない。

### 2.2 Account更新

- 外部入力として渡されたAccount更新候補を信頼せず、構造検証とFLS除去を行う。
- 更新権限がない項目を除去し、除去後のAccountだけをDMLへ渡す。
- 実行ユーザーのCRUD、FLS、レコード共有を適用する。
- DMLは部分成功とし、入力ごとの成功・失敗を同じindexで返す。
- FLSで除去したAccount項目名をResponse全体の集合として返す。
- 元の入力ListとAccountを変更しない。
- SOQLは実行せず、DMLをループ外で最大1回実行する。

## 3. 対象範囲と責務

### 3.1 コンポーネント

| コンポーネント | 責務 |
| --- | --- |
| `AccountQueryService` | Account Id集合の検証、USER_MODE SOQL、決定的順序でのAccount返却 |
| `AccountUpdateService` | Account更新候補の検証、FLS除去、USER_MODE部分更新、Response変換 |
| `AccountUpdateResponse` | リクエスト全体の除去項目と入力別結果の保持 |
| `AccountUpdateItemResult` | 元入力1件に対応する成功・失敗結果の保持 |
| `AccountUpdateError` | 1件の`Database.Error`を呼出元向けに保持 |
| `AccountQueryServiceTest` | Account参照の正常、境界、CRUD、FLS、共有、200件を証明 |
| `AccountUpdateServiceTest` | Account更新の正常、構造異常、FLS、CRUD、共有、部分成功、200件を証明 |

### 3.2 QueryとUpdateを別クラスにする理由

- QueryとUpdateは独立して呼び出される。
- QueryはUSER_MODE SOQLによるfail-fastを採用する。
- Updateは`stripInaccessible()`によるgraceful degradationとUSER_MODE DMLによる部分成功を採用する。
- 戻り値、失敗契約、変更理由が異なる。
- 権限制御という共通点だけで1クラスへ集約すると、将来責務が肥大化する。

### 3.3 行わない処理

- system modeへの権限昇格
- Account所有者や共有設定の変更
- Account以外の業務オブジェクト処理
- 業務項目値の補正
- 業務上の重複Account判定
- 入力データの分割
- 非同期化
- 失敗後の再試行
- 複数トランザクション全体の進捗・成功管理
- ガバナ制限残量の事前保証

同じAccount Idの入力重複は業務重複判定ではなく、入力構造検証としてUpdateサービス内で拒否する。

## 4. AccountQueryService 詳細設計

### 4.1 クラス契約

| 項目 | 内容 |
| --- | --- |
| クラス名 | `AccountQueryService` |
| 可視性 | `public` |
| sharing | `with sharing` |
| instance状態 | 持たない想定 |
| constructor | 未確定。static専用としてprivateにするか、本人実装時に確定する |

`with sharing`は、現在のSOQLだけでなく将来クラスへ追加される処理も含めて、実行ユーザーのレコード共有をクラス全体の方針として明示するために採用する。

### 4.2 メソッド契約

| 項目 | 内容 |
| --- | --- |
| メソッド名 | `findReadableAccountsByIds` |
| 可視性 | `public` |
| static | 付ける |
| 引数 | `Set<Id> accountIds` |
| 戻り値 | `List<Account>` |

想定シグネチャ:

```apex
public static List<Account> findReadableAccountsByIds(Set<Id> accountIds)
```

### 4.3 入力検証

| 入力 | 動作 | 完全なmessage | SOQL |
| --- | --- | --- | ---: |
| `accountIds == null` | `IllegalArgumentException` | `Account ID set must not be null.` | 0 |
| 空Set | 非nullの空Listをreturn | なし | 0 |
| Set内にnull | `IllegalArgumentException` | `Account ID set must not contain null.` | 0 |
| Account以外のId | `IllegalArgumentException` | `Account ID set must contain only Account IDs.` | 0 |

検証では、Idの`sObjectType`がAccountであることを確認する。入力Setはコピー、要素削除、追加、並べ替えを行わず、処理後も変更しない。

### 4.4 SOQL契約

- 実行回数: 非空かつ構造検証を通過した入力につき1回
- アクセスモード: 明示的な`WITH USER_MODE`
- SELECT:
  - `Id`
  - `Name`
  - `AccountNumber`
- WHERE: Account Idが入力Setに含まれること
- ORDER BY: `AccountNumber ASC NULLS LAST, Id ASC`
- ループ内SOQL: なし

`Id`は入力との対応付け、`Name`はAccountの識別、`AccountNumber`は業務上の識別とFLS確認のために取得する。

### 4.5 結果契約

- 戻り値は常に非nullの`List<Account>`とする。
- 存在しないAccount Idは結果へ含めない。
- 共有で参照できないAccountは結果へ含めない。
- 条件に一致する参照可能Accountが0件なら空Listを返す。
- 共有で見えないAccountがあっても、それ自体を理由とする例外は送出しない。
- Account Read CRUDまたはSELECT対象項目のFLS不足は`System.QueryException`をそのまま伝播する。
- Service内ではQueryExceptionをcatch、変換しない。
- `stripInaccessible()`とSchema describeによる独自分岐は使用しない。

### 4.6 並び順

- 第1キーはAccountNumber昇順。
- AccountNumberがnullのレコードは最後。
- 同じAccountNumberではId昇順。
- テストでは同じAccountNumberのAccount Idを`List<Id>`へ入れて`sort()`し、Idタイブレークの期待順を作る。
- MapやSetの反復順には依存しない。

## 5. AccountUpdateService 詳細設計

### 5.1 クラス契約

| 項目 | 内容 |
| --- | --- |
| クラス名 | `AccountUpdateService` |
| 可視性 | 未確定。組織内他クラスから利用する前提では`public`候補 |
| sharing | 未確定。DMLは明示的USER_MODEで共有を適用する |
| instance状態 | 持たない想定 |
| constructor | 未確定。static専用としてprivateにするか、本人実装時に確定する |

### 5.2 メソッド契約

| 項目 | 内容 |
| --- | --- |
| メソッド名 | `updateAccountsWithUpdatableFields` |
| 可視性 | `public` |
| static | 付ける |
| 引数 | `List<Account> accounts` |
| 戻り値 | `AccountUpdateResponse` |

想定シグネチャ:

```apex
public static AccountUpdateResponse updateAccountsWithUpdatableFields(
    List<Account> accounts
)
```

### 5.3 DTO契約

#### `AccountUpdateResponse`

| 項目 | 型 | 契約 |
| --- | --- | --- |
| `removedFields` | `Set<String>` | リクエスト全体でFLSにより除去されたAccount項目名。常に非null |
| `results` | `List<AccountUpdateItemResult>` | 入力ごとの結果。正常return時は入力と同件数・同順序。常に非null |

#### `AccountUpdateItemResult`

| 項目 | 型 | 契約 |
| --- | --- | --- |
| `inputIndex` | `Integer` | 元入力index。`results[i].inputIndex == i` |
| `accountId` | `Id` | 成功／失敗とも元入力`accounts[i].Id` |
| `success` | `Boolean` | 除去後AccountのDML成功可否 |
| `errors` | `List<AccountUpdateError>` | 成功時は非nullの空List、失敗時は全Database.Errorの変換結果 |

#### `AccountUpdateError`

| 項目 | 型 | 契約 |
| --- | --- | --- |
| `statusCode` | `System.StatusCode` | `Database.Error.getStatusCode()` |
| `message` | `String` | `Database.Error.getMessage()` |
| `fields` | `List<String>` | `Database.Error.getFields()` |

DTOを`AccountUpdateService`のpublic内側クラスにするか、独立publicクラスにするかは未確定である。public変数、プロパティ、constructorのどれで値を設定するかも本人実装と並行して確定する。

### 5.4 正常return時の不変条件

- `response != null`
- `response.removedFields != null`
- `response.results != null`
- `response.results.size() == accounts.size()`
- `response.results[i].inputIndex == i`
- `response.results[i]`は`accounts[i]`のDML結果を表す。
- `response.results[i].accountId == accounts[i].Id`
- 入力Listの件数、順序、要素参照を変更しない。
- 各入力AccountのIdと設定済み項目値を変更しない。
- 例外送出時はResponseを返さないため、この結果不変条件の対象外とする。

### 5.5 入力検証

| 入力 | 動作 | 完全なmessage | DML文／行 |
| --- | --- | --- | ---: |
| List自体がnull | `IllegalArgumentException` | `Account update candidate list must not be null.` | 0／0 |
| 空List | 空Responseをreturn | なし | 0／0 |
| List内の要素がnull | `IllegalArgumentException` | `Account update candidate must not be null. inputIndex={n}` | 0／0 |
| `Account.Id == null` | `IllegalArgumentException` | `Account.Id must not be null for update operations. inputIndex={n}` | 0／0 |
| Account以外のId | `IllegalArgumentException` | `Account.Id must belong to the Account object. inputIndex={n}` | 0／0 |
| 同じIdが重複 | `IllegalArgumentException` | `Duplicate Account.Id is not allowed. firstInputIndex={first}, duplicateInputIndex={duplicate}` | 0／0 |

全入力の構造検証をDML前に完了する。構造違反がある場合は入力全体を例外として扱い、DBを変更しない。

### 5.6 処理順

1. List自体のnullを検証する。
2. 空Listなら、空の`removedFields`と`results`を持つResponseを返す。
3. List内の全要素について、null、Id、sObjectType、重複Idを検証する。
4. `Security.stripInaccessible()`を実行する。
5. `SObjectAccessDecision.getRecords()`から除去後のAccount Listを取得する。
6. `getRemovedFields()`のAccountキーから除去項目を取得する。キーがなければ空Setとする。
7. 除去後Account Listを1回の部分成功DMLへ渡す。
8. `SaveResult[i]`を元入力index `i`の`AccountUpdateItemResult`へ変換する。
9. `AccountUpdateResponse`を返す。

### 5.7 `stripInaccessible()`契約

| 項目 | 値 |
| --- | --- |
| AccessType | `System.AccessType.UPDATABLE` |
| enforceRootObjectCRUD | `true` |
| DMLへ渡すList | `SObjectAccessDecision.getRecords()` |
| removed fields | `getRemovedFields()`のAccountキーに対応するSet |

`enforceRootObjectCRUD = true`とし、Account Update CRUD不足はstrip実行時点で`System.NoAccessException`としてfail-fastにする。Service内でcatch、変換せず、そのまま呼出元へ伝播する。

`stripInaccessible()`は元のList・sObjectを変更せず、入力順を維持した除去後Listを返し、DMLに必要なIdを除去しない。このためcloneは使用しない。

### 5.8 DML契約

| 項目 | 値 |
| --- | --- |
| API | `Database.update` |
| allOrNothing | `false` |
| accessLevel | `System.AccessLevel.USER_MODE` |
| DML文数 | 空入力0、非空かつ構造検証通過時1 |
| DML行数 | 除去後Listの件数。入力件数と同じ |

成功`SaveResult`は成功Id、`success = true`、空errorsへ変換する。失敗`SaveResult.getId()`は空であるため、失敗結果の`accountId`も元入力`accounts[i].Id`から取得する。

1つの`SaveResult`に複数の`Database.Error`がある場合、すべてを個別の`AccountUpdateError`へ変換する。

### 5.9 成功・失敗の意味

- `success = true`は、FLS除去後のAccountのDMLが成功したことを意味する。
- 元入力の全項目が更新されたことは意味しない。
- 適用されなかった項目はResponseの`removedFields`で確認する。
- レコード単位の入力規則、重複ルール、共有不足等は失敗ItemResultへ変換する。
- `allOrNothing=false`のため、他レコードの成功を妨げない。
- ガバナ制限超過、Trigger／Flowの未処理例外等のトランザクション全体エラーではResponseを返さず、先行成功分を含めて全体がロールバックする。

## 6. セキュリティ設計

### 6.1 セキュリティ層

| 層 | Query | Update |
| --- | --- | --- |
| Apex Class Access | 実際の外部entry point側で管理。内部Service用Permission Setには含めない | 同左 |
| CRUD | `WITH USER_MODE`でAccount Readをfail-fast | `stripInaccessible(..., true)`とUSER_MODE DMLでAccount Updateを適用 |
| FLS | `WITH USER_MODE`でSELECT項目をfail-fast | `UPDATABLE`で除去し、removedFieldsで通知。USER_MODE DMLでも適用 |
| レコード共有 | `with sharing`と`WITH USER_MODE` | USER_MODE DMLで適用。クラスsharingは未確定 |

### 6.2 Queryでfail-fastを採用する理由

- `Id`、`Name`、`AccountNumber`は要件として参照が必要である。
- 必須項目を黙って除外すると、呼出元が不完全なAccountを正常結果として扱う可能性がある。
- 権限不足時の独自分岐は必要ないため、QueryExceptionをそのまま伝播する。

### 6.3 Updateでgraceful degradationを採用する理由

- 外部入力には、実行ユーザーが更新できない項目が含まれる可能性がある。
- 更新不可項目だけを除去し、許可項目の更新は継続する要件である。
- 除去項目名をResponseへ返し、呼出元が適用されなかった項目を確認できる。
- 除去後もUSER_MODE DMLを使い、CRUD、FLS、共有、restriction rule等の最終適用をプラットフォームへ委ねる。

## 7. テストデータ・権限設計

### 7.1 基本方針

- テストクラスは`SeeAllData=false`とする。
- Account等の業務データは各テスト内で作成する。
- Profileは`Minimum Access - Salesforce`を使用する。
- User LicenseはSalesforceを使用する。
- Permission SetはメタデータとしてGit管理する。
- Permission Set Assignmentはテスト内で作成する。
- 内部ServiceのApex Class AccessはPermission Setへ含めない。

### 7.2 Permission Set

| Permission Set | 権限 |
| --- | --- |
| `Account_Query_Basic` | Account Read、`AccountNumber` Read |
| `Account_Query_Without_Number` | Account Read、`AccountNumber` FLSなし |
| `Account_Update_Safe` | Account Read／Edit、`Phone` Read／Edit、`AccountNumber` Readのみ、`AnnualRevenue` Readのみ |

`Account.Name`はpermissionableでない可能性があるため、API 67.0環境で`isPermissionable()`を実測する。falseならName FLS不足の独立テストは作成不能として記録し、テスト対象外とする。

### 7.3 共有設定

- Account OWD: Private
- ownerUserとreaderUserには、どちらもRoleを設定しない。
- Role階層による参照経路を作らず、組織に既存するRoleにも依存しない。
- 共有ルール: なし
- 手動共有: なし
- Account View All／Modify All: なし
- View All Data／Modify All Data: なし

共有テストでは、Visible AccountをreaderUser所有、Hidden AccountをownerUser所有とする。両ユーザーはRole未設定とし、所有者の違いとOWD Privateだけで可視性を分離する。

### 7.4 `@TestSetup`とMixed DML

`@TestSetup`ではSetupオブジェクトだけを作成する。

- Roleを設定しない用途別User
- PermissionSetAssignment

各テストメソッドでは非SetupオブジェクトのAccountを作成する。Accountは管理権限を持つテスト実行ユーザーがinsertし、必要な`OwnerId`を明示する。

これにより、User、PermissionSetAssignmentとAccountのDMLを別実行段階へ分離する。

### 7.5 `System.runAs`とLimits

概念上の配置:

1. `@TestSetup`でRole、User、PermissionSetAssignmentを作成する。
2. 各テストでAccountと入力を準備する。
3. 対象Userを`System.runAs()`へ渡す。
4. runAs内で`Test.startTest()`を実行する。
5. サービス呼出し直前にLimits beforeを取得する。
6. サービスを呼び出す。
7. 直後にLimits afterを取得する。
8. `Test.stopTest()`を実行する。
9. DBとResponseをAssertする。

Role自体ではなく、そのRoleに所属するUserを`System.runAs()`へ渡す。

## 8. AccountQueryServiceTest 詳細設計

### 8.1 テスト一覧

| # | テストメソッド名 | 証明内容 |
| ---: | --- | --- |
| 1 | `findReadableAccountsByIds_withMultipleAccounts_returnsInDeterministicOrder` | AccountNumber、NULLS LAST、Idタイブレークの決定的順序 |
| 2 | `findReadableAccountsByIds_withNullInput_throwsIllegalArgumentException` | null Set拒否、SOQL 0 |
| 3 | `findReadableAccountsByIds_withEmptySet_returnsEmptyListWithoutQuery` | 空Set、非null空List、SOQL 0 |
| 4 | `findReadableAccountsByIds_containingNull_throwsIllegalArgumentException` | Set内null拒否、SOQL 0 |
| 5 | `findReadableAccountsByIds_containingNonAccountId_throwsIllegalArgumentException` | 異種Id拒否、SOQL 0 |
| 6 | `findReadableAccountsByIds_withOnlyNonexistentId_returnsEmptyList` | 非存在Idだけの場合、1 SOQL・0行・空Listを返す |
| 7 | `findReadableAccountsByIds_withExistingAndNonexistentIds_returnsOnlyExistingAccount` | 実在Idと非存在Idの混在時、実在Accountだけを返す |
| 8 | `findReadableAccountsByIds_withUnsharedAccount_omitsInvisibleAccount` | 共有で見えないAccountの正常除外 |
| 9 | `findReadableAccountsByIds_withoutAccountReadPermission_throwsQueryException` | Account Read CRUD不足のfail-fast |
| 10 | `findReadableAccountsByIds_withoutAccountNumberReadAccess_throwsQueryException` | AccountNumber Read FLS不足のfail-fast |
| 11 | `findReadableAccountsByIds_withTwoHundredAccounts_returnsAllAccounts` | 200件を1 SOQLで全件取得 |
| 12 | `findReadableAccountsByIds_withValidIds_usesOneQueryAndDoesNotModifyInput` | SOQL 1回と入力Set不変性 |

Name FLS不足テストは`Account.Name.isPermissionable()`のAPI 67.0実測後に要否を確定する。

### 8.2 決定的順序

- AccountNumberが`A-001`、`B-002`、nullのAccountを含める。
- 同じAccountNumberのAccountを2件以上含める。
- AccountNumber昇順、nullは最後とする。
- 同一AccountNumber内の期待Idは`List<Id>.sort()`で決める。
- 全件のId、Name、AccountNumberをindexごとに確認する。
- 入力Setの反復順には依存しない。

### 8.3 非存在Id

```apex
private static final Id NONEXISTENT_ACCOUNT_ID = '001000000000001';
```

- 実在1件＋非存在Id:
  - SOQL 1
  - Query rows 1
  - 例外なし
  - 非nullList 1件
  - 実在Accountだけを含む
- 非存在Idだけ:
  - SOQL 1
  - Query rows 0
  - 例外なし
  - 非nullの空List

### 8.4 共有除外

- 入力SetへVisible AccountとHidden Accountの両Idを入れる。
- readerUserとして実行する。
- readerUserは`Account_Query_Basic`を持ち、View All／Modify Allを持たない。
- 期待結果はVisible Accountだけの1件。
- Hidden Accountが含まれず、例外も発生しない。

### 8.5 CRUD／FLS不足

- Account CRUD不足:
  - Account関連Permission Setを付与しない。
  - 実在Account Idを1件渡す。
  - QueryExceptionを伝播する。
  - 戻り値なし。
  - 失敗したSOQLもLimits上は1回の試行として期待する。実測差異があれば更新する。
- AccountNumber FLS不足:
  - `Account_Query_Without_Number`だけを付与する。
  - 対象Accountは実行ユーザー所有とし、共有の影響を除外する。
  - Account ReadがあってもSELECT対象AccountNumberのFLS不足によりQueryExceptionを期待する。

### 8.6 200件

- AccountNumberは`ACC-001`から`ACC-200`。
- Account 200件を一括insertする。
- 入力Setへ全Idを入れる。
- 結果件数200件。
- 全indexのId、Name、AccountNumberをループで確認する。
- SOQL文差分1。
- Query rows差分200。

## 9. AccountUpdateServiceTest 詳細設計

### 9.1 テスト一覧

| # | テストメソッド名 | 証明内容 |
| ---: | --- | --- |
| 1 | `updateAccountsWithUpdatableFields_withValidAccounts_returnsSuccessResults` | 正常更新と成功Response |
| 2 | `updateAccountsWithUpdatableFields_withMultipleAccounts_preservesResultOrder` | 入力indexと結果indexの対応 |
| 3 | `updateAccountsWithUpdatableFields_withTwoHundredAccounts_updatesAllAccounts` | 200件の一括更新 |
| 4 | `updateAccountsWithUpdatableFields_withValidAccounts_usesOneDmlStatement` | DML 1文・入力件数行 |
| 5 | `updateAccountsWithUpdatableFields_doesNotModifyInputListOrAccounts` | 入力List・Account不変性 |
| 6 | `updateAccountsWithUpdatableFields_withNullInput_throwsIllegalArgumentException` | null List拒否、DML 0 |
| 7 | `updateAccountsWithUpdatableFields_withEmptyList_returnsEmptyResponseWithoutDml` | 空Response、DML 0 |
| 8 | `updateAccountsWithUpdatableFields_containingNull_throwsIllegalArgumentException` | List内null拒否、DML 0 |
| 9 | `updateAccountsWithUpdatableFields_containingAccountWithoutId_throwsIllegalArgumentException` | Idなし拒否、DML 0 |
| 10 | `updateAccountsWithUpdatableFields_containingNonAccountId_throwsIllegalArgumentException` | 異種Id拒否、DML 0 |
| 11 | `updateAccountsWithUpdatableFields_containingDuplicateId_throwsIllegalArgumentException` | 重複Id拒否、DML 0 |
| 12 | `updateAccountsWithUpdatableFields_withInaccessibleField_removesFieldAndUpdatesAccessibleFields` | 許可項目だけDB更新 |
| 13 | `updateAccountsWithUpdatableFields_withRemovedFields_returnsAggregateRemovedFields` | 複数入力の除去項目をResponseへ集約 |
| 14 | `updateAccountsWithUpdatableFields_withoutAccountUpdatePermission_throwsNoAccessException` | Update CRUD不足、DML 0 |
| 15 | `updateAccountsWithUpdatableFields_withValidAndInvalidAccounts_returnsPartialResults` | 同一DMLの部分成功 |
| 16 | `updateAccountsWithUpdatableFields_whenFieldLengthExceedsLimit_returnsDmlErrors` | Database.ErrorのDTO変換 |
| 17 | `updateAccountsWithUpdatableFields_whenRecordIsNotUpdatable_returnsFailureResult` | 共有アクセス不足を失敗結果へ変換 |

### 9.2 空・構造異常

- 空ListのResponse:
  - `response != null`
  - `removedFields != null`
  - `removedFields.size() == 0`
  - `results != null`
  - `results.size() == 0`
  - DML文0、行0、DB変更0
- 構造異常:
  - 項目5.5の完全messageを確認する。
  - List内nullはinputIndex 1。
  - Idなし／異種IdはinputIndex 0。
  - 重複IdはfirstInputIndex 0、duplicateInputIndex 2。
  - DML文0、行0、DB変更0。

### 9.3 FLS除去後の更新

テストユーザー:

- Account Read／Edit
- Phone Read／Edit
- AccountNumber Readのみ

更新前:

- Phone=`03-1111-1111`
- AccountNumber=`OLD-001`

入力:

- Phone=`03-2222-2222`
- AccountNumber=`NEW-001`

期待結果:

- 結果1件、成功、元入力Id、空errors。
- removedFieldsに`AccountNumber`を含む。
- DB上のPhoneは`03-2222-2222`。
- DB上のAccountNumberは`OLD-001`のまま。
- DML文1、行1。

### 9.4 aggregate removed fields

- Account A: Phoneと更新不可AccountNumberを設定する。
- Account B: Phoneと更新不可AnnualRevenueを設定する。
- removedFieldsは2件。
- `AccountNumber`と`AnnualRevenue`を含む。
- `Phone`を含まない。
- 結果2件は入力index 0、1に対応し、どちらも成功、空errors。

### 9.5 部分成功

入力順:

- index 0 Account A: 正常なPhone=`03-2222-2222`
- index 1 Account B: 最大40文字を超える41文字のPhone

期待結果:

- DML文1、行2。
- 結果2件。
- index 0は成功、AのId、空errors、DB更新あり。
- index 1は失敗、Bの元入力Id、1件以上のerrors、DB更新なし。
- 失敗レコードも試行したDML行へ含める。

### 9.6 DMLエラー変換

- Phoneへ41文字を設定したAccount 1件を渡す。
- 結果1件、inputIndex 0、失敗、元入力Id。
- errors 1件を暫定期待とする。
- 暫定StatusCodeは`STRING_TOO_LONG`。
- 暫定fieldsは`Phone`を含む。
- messageは非空。
- DB上のPhoneは更新前値。
- DML文1、行1。

StatusCode、fields、エラー件数、messageはAPI 67.0スクラッチ組織で実測し、異なる場合は実測結果を正本へ反映する。

### 9.7 共有アクセス不足

- ownerUser所有でreaderUserへ共有されていないAccountを用意する。
- readerUserはAccount Read／Edit、Phone Editを持つが、View All／Modify Allを持たない。
- Phone更新候補を1件渡す。
- メソッドは例外ではなくResponseを返す。
- 結果1件、失敗、元入力Id、共有アクセス不足のDMLエラー。
- DB上のPhoneは変更されない。
- DML文1、行1。

### 9.8 CRUD不足

- Account Editを持たず、`Account_Query_Basic`だけを付与したユーザーで実行する。
- `System.NoAccessException`を期待する。
- DML文0、行0、DB変更0。
- Responseは返らない。
- 元入力は変更されない。

例外型はAPI 67.0で実測し、異なる場合は実測結果を正本へ反映する。

### 9.9 200件

- 入力件数200、結果件数200。
- 全indexでinputIndex、元入力Id、成功、空errorsを確認する。
- DML文1、行200。
- DBからIdで一括再取得し、`Map<Id, Account>`として全200件の更新値を確認する。
- SOQL結果順には依存しない。

### 9.10 入力不変性

処理前に次を保持する。

- List件数
- 各indexのAccount参照
- 各AccountのId
- 更新可能項目値
- FLS除去対象項目値

処理後に次を確認する。

- List件数と順序が同じ。
- 各indexのAccountが`===`で処理前と同一参照。
- 元AccountのIdと全設定項目値が同じ。
- DB上では更新可能項目だけが更新される。
- FLS除去項目はDB上で更新前値を維持する。

## 10. ガバナ制限・データ量

### 10.1 現時点で確定した使用量

| 処理 | 空入力 | 非空入力 |
| --- | ---: | ---: |
| Query SOQL文 | 0 | 1 |
| Query rows | 0 | 参照可能かつ存在する一致Account件数 |
| Update SOQL文 | 0 | 0 |
| Update DML文 | 0 | 1 |
| Update DML行 | 0 | DMLへ渡したAccount件数 |

1回の想定利用規模は200件とする。ただし、サービス自身に200件の固定上限は設けない。

### 10.2 呼出元の責務

- 200件超の入力分割
- 10,000 DML rowsを含むトランザクション全体の使用量管理
- 50,000 Query rowsを含むトランザクション全体の使用量管理
- 非同期化
- 失敗後の再試行
- 複数バッチの成功・失敗集計
- Trigger、Flow、他Serviceを含むCPU・ヒープ・SOQL・DML残量の管理

### 10.3 未確定

- Queryの厳密な時間計算量と追加ヒープ量
- Updateの厳密な時間計算量と追加ヒープ量
- 入力件数`n`、DMLエラー総数`e`、除去項目数`f`を用いた最終表現
- 上限到達時の具体例

これらは本人実装後に、実際のList、Set、Map、DTO、helper構成を基に項目8として確定する。

## 11. 設計判断と代替案

### 11.1 現時点で採用済み

| 論点 | 採用 | 理由 |
| --- | --- | --- |
| クラス分割 | Query／Updateを別クラス | セキュリティ方式、戻り値、失敗契約、変更理由が異なる |
| Queryの権限不足 | USER_MODEでfail-fast | 必須項目を除外した不完全なAccountを返さない |
| UpdateのFLS | strip＋USER_MODE DML | 更新不可項目を除外して許可項目を継続し、DB操作は最終的にユーザー権限で実行 |
| Updateの原子性 | `allOrNothing=false` | 入力ごとの成功・失敗をResponseへ返す |
| removed fields | Response全体のSet | 実行ユーザーのリクエスト全体で除去されたAccount項目を通知する |
| Role | 両ユーザーとも未設定 | Role階層による参照経路と組織の既存Roleへの依存を排除する |
| clone | 不採用 | stripが元入力を変更せず、順序とIdを維持した除去後Listを返す |

### 11.2 項目8で説明を追加する代替案

- QueryとUpdateを1クラスへまとめる案
- Queryで`stripInaccessible(READABLE)`を使う案
- UpdateでUSER_MODE DMLだけを使う案
- `allOrNothing=true`案
- removed fieldsを入力ごとに返す案
- Roleをメタデータ管理する案
- DTOを独立クラスにする案とService内側クラスにする案
- public constructorとprivate constructor

## 12. 未確定事項・実測事項

### 12.1 実装と並行して確定する事項

- `AccountUpdateService`のクラス可視性とsharing宣言
- 両Serviceのconstructor可視性
- DTOを内側クラス／独立クラスのどちらにするか
- DTOのpublic変数／プロパティ／constructor設計
- private helperの分割単位
- Query／Updateの計算量とヒープ
- 代替案比較の最終説明
- 最終リスク整理

### 12.2 API 67.0実測事項

- `Account.Name.isPermissionable()`
- Phone 41文字時のStatusCode、fields、message、エラー件数
- Account Update CRUD不足時の例外型
- CRUD／FLS不足QueryException時のLimits Query差分
- 共有アクセス不足時のStatusCode、fields、message
- User／PermissionSetAssignmentを`@TestSetup`、Accountを各テストで作る構成のMixed DML実行結果
- `getRemovedFields()`のAccountキーと返却項目名

実測値が暫定期待値と異なる場合、テストだけを実測へ合わせず、要件上許容できる差かを判断してこの設計書も更新する。

## 13. 実装・検証状態

| 対象 | 状態 |
| --- | --- |
| Gate A本人説明 | 100%・commit `69a0120`確認済み |
| Gate B項目1〜7 | 確認済み |
| Gate B項目8 | 未完了・本人実装と並行確定 |
| `AccountQueryService` | 本人提出・静的レビュー済み。API 67.0コンパイル未確認 |
| `AccountUpdateService` | 未提出 |
| DTO | 未提出 |
| Permission Set | 3件提出。最終静的レビュー・デプロイ未確認 |
| Role／共有環境 | 2ユーザーともRole未設定の設計へ同期。実動作未確認 |
| Queryテスト | 12件提出・静的レビュー済み。API 67.0実行未確認 |
| Updateテスト | 未提出 |
| API 67.0実測 | 未実施 |
| デプロイ | 未実施 |
| 静的解析 | 未実施 |
| Evidence | 未作成 |

Gate Bは88%（7/8）のままである。Gate CはQuery側の本人実装が部分提出されたが、Update側、API 67.0実測、デプロイ、静的解析、Evidence、本人自己確認が未完了である。設計書や静的レビューだけを実行成功の証拠とはしない。

## 14. 設計判断履歴

| 日付 | 判断 |
| --- | --- |
| 2026-10-21 | QueryとUpdateを別Serviceへ分離し、外部入力を信頼しない方針を確定 |
| 2026-10-22 | Queryの入力、戻り値、項目、順序、USER_MODE、fail-fast、with sharingを確定 |
| 2026-10-23 | UpdateのDTO、構造検証、FLS除去、USER_MODE部分成功、トランザクション境界を確定 |
| 2026-10-23 | clone案を撤回し、stripの返却ListをDMLへ渡す方針へ変更 |
| 2026-10-25 | Query 11件、Update 17件のテスト一覧、Permission Set、OWD、Role構成を設計 |
| 2026-10-26 | 境界、200件、不変性、非存在Id、Limits、Mixed DML分離を具体化し、Gate B項目7を完了 |
| 2026-10-26 | Gate B項目8を本人実装と並行して確定する方針へ変更 |
| 2026-10-30 | Query共有テストをRole未設定へ変更し、Role階層と既存Roleへの依存を排除 |
| 2026-10-30 | 非存在Idだけと実在Id混在を分離し、Queryテストを12件へ更新。Query本体・テストの静的レビューを完了 |

