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
| 状態 | CP6完了。実装・テスト・検証済み |
| 作成日 | 2026-10-26 |
| 最終更新日 | 2026-11-15 |
| 検証結果 | [匿名化した検証サマリー](../evidence/README.md#cp6-security-recipes) |

この文書は、Accountの検索と更新の実装契約・設計判断・検証結果を整理した公開版である。

クラスAPI、DTO配置、計算量、代替案、残る制約を実装とスクラッチ組織での実測に照らし合わせた。[CP6の検証証拠](../evidence/README.md#cp6-security-recipes)に実デプロイと回帰テストの結果を記録する。

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
| instance状態 | 持たない |
| constructor | private。staticメソッドで利用するため、呼出元からのinstance生成を防ぐ |

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

要件からDTO・メソッド構成を決めた理由は、[AccountUpdateServiceを設計した流れ](CP6_ACCOUNT_UPDATE_DESIGN_PROCESS.md)に記録する。本章は現在の実装契約、別紙は設計に至った経緯として参照する。

### 5.1 クラス契約

| 項目 | 内容 |
| --- | --- |
| クラス名 | `AccountUpdateService` |
| 可視性 | `public`を採用 |
| sharing | `with sharing`を採用。DMLも明示的USER_MODEで共有を適用する |
| instance状態 | 持たない |
| constructor | static専用としてprivateを採用 |

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

DTOは`AccountUpdateService`のpublic内側クラスとする。このService専用の型を独立クラスへ分散させず、呼出元からは`AccountUpdateService.AccountUpdateResponse`などの型名で参照する。

各項目は`public ... { get; private set; }`のプロパティとし、public constructorで値をまとめて設定する。呼出元からプロパティの再代入はできないが、List・Setの内容まで変更不可とする契約ではない。正常return時の不変条件はServiceが返すDTOに対する保証であり、呼出元がconstructorで任意に作るDTOを検証するものではない。

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
| Account以外のId | `Account.Id`への代入時に`System.TypeException` | messageに`Invalid id value for this SObject type`を含む | 0／0 |
| 同じIdが重複 | `IllegalArgumentException` | `Duplicate Account.Id is not allowed. firstInputIndex={first}, duplicateInputIndex={duplicate}` | 0／0 |

全入力の構造検証をDML前に完了する。構造違反がある場合は入力全体を例外として扱い、DBを変更しない。異種Idについては、今回テストした型付き`Account.Id`への代入でService呼出し前に拒否される。Service側のsObjectTypeチェックも防御として残す。

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
| DML文数 | 空入力・構造検証例外・strip時のCRUD例外では0。DML到達時は1 |
| DML行数 | 除去後Listの件数。入力件数と同じ |

成功時は`success = true`と空errors、失敗時は`success = false`と全Database.Errorの変換結果を設定する。`accountId`は成功・失敗とも元入力`accounts[i].Id`から取得し、どの入力の結果かを常に同じ方法で特定する。

失敗時の`SaveResult.getId()`が常にnullとは限らない。公式仕様ではAPI 53.0以降は対象Idを返し、更新時のレコードロック失敗ではnullになる。元入力Idを使うことでこの挙動に依存しない。[公式仕様：SaveResult.getId()](https://developer.salesforce.com/docs/platform/apex-ref/references/apex-ref/apex-methods-system-database-saveresult.html)

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
| レコード共有 | `with sharing`と`WITH USER_MODE` | `with sharing`を明示し、USER_MODE DMLでも適用 |

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
| `Account_Update_Without_Phone` | Account Read／Edit、`Phone` Readのみ。Update共有テストの別所有者に割り当てる |

API 67.0のAccount describeで`Name.permissionable=false`を確認した。NameのFLS不足を独立して設定するテストは対象外とし、AccountNumberでFLS不足を検証する。

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

1. `@TestSetup`でRole未設定のUserとPermissionSetAssignmentを作成する。
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
  - 2026-10-31のAPI 67.0クラスでの実測は、QueryException送出・SOQL回数差分0・取得行数差分0。旧APIからの仕様変更とまでは断定しない。
- AccountNumber FLS不足:
  - `Account_Query_Without_Number`だけを付与する。
  - 対象Accountは実行ユーザー所有とし、共有の影響を除外する。
  - Account ReadがあってもSELECT対象AccountNumberのFLS不足によりQueryExceptionを期待する。
  - 同日のAPI 67.0クラスでの実測は、SOQL回数差分0・取得行数差分0。

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
| 10 | `assigningNonAccountIdToAccount_throwsTypeExceptionBeforeService` | 型付き`Account.Id`への異種Id代入をService呼出し前に拒否、DML 0 |
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
- Service内の構造検証は項目5.5の完全messageを確認する。異種Id代入は`TypeException`のmessageに所定の文字列を含むことを確認する。
  - List内nullはinputIndex 1。
  - IdなしはinputIndex 0。
  - 異種Idは`Account.Id`への代入時点で`System.TypeException`となり、Serviceへ到達しない。
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
- errors 1件。
- StatusCodeは`STRING_TOO_LONG`。
- fieldsは`Phone`を含む。
- messageは非空。
- DB上のPhoneは更新前値。
- DML文1、行1。

上記はAPI 67.0のテストで確認済み。message本文の完全一致は契約に含めない。

### 9.7 共有アクセス不足

- ownerUser所有でreaderUserへ共有されていないAccountを用意する。
- readerUserはAccount Read／Edit、Phone Editを持つが、View All／Modify Allを持たない。
- Phone更新候補を1件渡す。
- メソッドは例外ではなくResponseを返す。
- 結果1件、失敗、元入力Id、共有アクセス不足のDMLエラー。
- API 67.0の実測StatusCodeは`INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY`。
- DB上のPhoneは変更されない。
- DML文1、行1。

### 9.8 CRUD不足

- Account Editを持たず、`Account_Query_Basic`だけを付与したユーザーで実行する。
- `System.NoAccessException`を期待する。
- DML文0、行0、DB変更0。
- Responseは返らない。
- 元入力は変更されない。

`System.NoAccessException`とDML 0文・0行はAPI 67.0のテストで確認済み。

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
| Query SOQL文 | 0 | 検索成功時1。CRUD／FLS拒否時は実測0 |
| Query rows | 0 | 参照可能かつ存在する一致Account件数。権限拒否時は実測0 |
| Update SOQL文 | 0 | 0 |
| Update DML文 | 0 | DMLに到達した場合は1。構造不正・root CRUD不足で実行前に拒否した場合は0 |
| Update DML行 | 0 | DMLへ渡したAccount件数。レコード単位の失敗分も含む |

1回の想定利用規模は200件とする。ただし、サービス自身に200件の固定上限は設けない。

### 10.2 呼出元の責務

- 200件超の入力分割
- 10,000 DML rowsを含むトランザクション全体の使用量管理
- 50,000 Query rowsを含むトランザクション全体の使用量管理
- 非同期化
- 失敗後の再試行
- 複数バッチの成功・失敗集計
- Trigger、Flow、他Serviceを含むCPU・ヒープ・SOQL・DML残量の管理

### 10.3 計算量・追加ヒープと制限超過例

- Query: 入力Id件数`n`、返却件数`m`。Apexの入力検証は`O(n)`、レコードサイズ一定とした返却Listは`O(m)`。DB側の検索とソート時間は含めない。
- Update: 入力件数`n`、DMLエラー総数`e`、除去項目名の種類数`f`。`SaveResult`を入力順に走査し、各エラーを合計`e`回処理する結果変換は`O(n + e)`。
- Updateの追加ヒープは、レコード・エラーサイズ一定の前提で`O(n + e + f)`。重複検証Map、除去後List、`SaveResult`と入力別DTOが`n`、エラー情報が`e`、除去項目集合が`f`に対応する。プラットフォーム内部の実行時間やヒープを断定するものではない。
- DML行数の残りが300行の同一トランザクションで200件更新を2回実行すると、2回目は残り100行を超える。`allOrNothing=false`でも100件だけ保存する動作にはならず、LimitExceptionで1回目を含めた同一トランザクションのDB変更がロールバックされる。
- 同一トランザクション内でリストを小分けしても消費枠は共通である。呼出元でトランザクションを分けた場合は、コミット単位も分かれるため、呼出元が結果の集計と再試行を管理する。

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
| UpdateのDTO配置 | public内側クラス | このService専用の型としてまとめ、呼出元から参照できる |
| UpdateのDTO設定 | get／private setとconstructor | 生成時に必要な値を渡し、呼出元のプロパティ再代入を防ぐ |
| Updateの内部準備結果 | private内側クラス | 除去後Accountと除去項目をまとめて後続処理へ渡す |

### 11.2 代替案と採用理由

- QueryとUpdateを統合すると、参照時のfail-fastと更新時の除去・部分成功という異なる契約を1クラスで扱う。今回は責務を分離する。
- Queryの`stripInaccessible(READABLE)`は読めない項目を除いた結果を返せるが、今回は必要項目が欠けた結果を成功として返さず、USER_MODE SOQLでfail-fastにする。
- UpdateでUSER_MODE DMLだけを使う場合、更新不可項目を含む対象レコードは失敗し、そのレコードの許可項目も更新されない。今回は除去後に許可項目を更新し、除去項目を通知する。
- `allOrNothing=true`では、同じDML内の1件の失敗でそのDML全体が取り消され、Responseは返らない。今回はレコードごとの成否を返せる`false`を採用する。
- レコード別の除去情報が必要なら、除去項目を`AccountUpdateItemResult`等へ持たせる。ただし全体集合だけから個別の内訳は復元できないため、入力別の除去情報を取得する処理も必要となる。現要件は全体集合とする。
- 共有テストはRoleをメタデータとして追加せず、Role未設定と所有者の違いで分離する。DTOはUpdate専用なのでServiceの内側に置く。
- 両Serviceはstatic専用とし、public constructorで不要なinstance生成を許さず、private constructorを採用する。
- `with sharing`はクラスのレコード共有方針を明示する。`USER_MODE`は対象DB操作でCRUD・FLS・レコード共有を適用するため、操作ごとに明示する。

## 12. 未確定事項・実測事項

### 12.1 確定事項と残る制約

- 両Serviceのクラス宣言・private constructor、DTO配置、計算量、代替案比較は第4・5・10・11章に反映した。
- 部分成功で扱うのはレコード単位のDMLエラーであり、トランザクション全体の失敗は対象外。入力分割、非同期化、集計、再試行は呼出元で管理する。
- 除去項目の通知は全体集合。入力別に表示する要件が追加された場合はDTOと除去情報の取得方法を再設計する。

### 12.2 API 67.0実測事項

- Account describeで`Name.permissionable=false`、`Phone.length=40`を確認。
- Phone 41文字は`STRING_TOO_LONG`、エラー1件、fieldsに`Phone`を含み、messageは非空。
- Account Update CRUD不足は`System.NoAccessException`、DML 0文・0行。
- CRUD／FLS不足QueryException時のSOQL文数・取得行数差分は各0。API 67.0での観測であり、旧APIとの比較は未実施。
- 共有アクセス不足は`INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY`を含む失敗結果、DB値は未変更。fields・message本文の完全一致は契約に含めない。
- User／PermissionSetAssignmentを`@TestSetup`、Accountを各テストで作る構成で対象29テストが成功し、Mixed DMLエラーは発生しなかった。
- Accountの除去項目名を返し、FLS除去テストで`AccountNumber`と`AnnualRevenue`の集合を確認。

実測の根拠は[CP6証拠](../evidence/README.md#cp6-security-recipes)を参照する。

## 13. 実装・検証状態

| 対象 | 状態 |
| --- | --- |
| `AccountQueryService` | API 67.0で実デプロイ済み、15/16箇所カバー（93.8%） |
| `AccountUpdateService` | API 67.0で実デプロイ済み、74/76箇所カバー（97.4%） |
| DTO | public内側3クラス、get／private set、constructor設定を採用。内部準備結果はprivate内側クラス |
| Permission Set | 4件実デプロイ済み |
| Role／共有環境 | テストユーザーはRole未設定。Queryの共有除外とUpdateの共有不足を実測確認 |
| Queryテスト | 12/12成功 |
| Updateテスト | 17/17成功。異種Idの型境界と、共有不足のStatusCodeを確認 |
| API 67.0実デプロイ | 2026-11-10、9/9成功、エラー0、`checkOnly=false` |
| 関連全テスト | `RunLocalTests` 123/123成功、失敗0、カバレッジ警告0 |
| 静的解析 | Critical／High 0、Moderate 44、Low 34、Info 11。指摘分類済み |
| 検証サマリー | [匿名化したCP6検証結果](../evidence/README.md#cp6-security-recipes)に掲載 |

上記は学習用スクラッチ組織での検証結果。公開版には実行環境を識別する情報や生ログを含めない。

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
| 2026-10-31 | Queryの対象12テスト成功を確認。CRUD／FLS不足時のSOQL回数・取得行数差分は0へ更新 |
| 2026-11-05 | Update本体とDTOをレビューし、API 67.0チェック専用デプロイ成功を確認。Updateテストは未提出 |
| 2026-11-06 | 提示された設計経緯を[別紙](CP6_ACCOUNT_UPDATE_DESIGN_PROCESS.md)へ保存。DTO配置・プロパティ・helper構成を記録し、SaveResultのIdに関する説明を訂正 |
| 2026-11-09 | Update 17テスト成功。異種IdのService前拒否と共有不足のStatusCodeを実測し、Assertを追加 |
| 2026-11-10 | Gate B項目8・Gate Cの本人説明を確認。Gate Dで実デプロイ9/9・関連全テスト123/123・静的解析と証拠保存を確認 |
| 2026-11-15 | CP6完了 |
