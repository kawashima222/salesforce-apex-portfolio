# CP5 Apexテスト 詳細設計書

- 作成日: 2026-10-13
- 状態: Gate B本人設計完了・Gate C本人実装待ち
- 対象branch: `feature/cp5-apex-tests`
- 根拠: `GOAL_SPEC.md`、`PLAN.md`、`LEARNING_PROGRESS.md`

## 1. 類似要件

CP1で作成した`CaseIndexService_Tests`を、CP5で学んだテストデータ分離、`@TestSetup`、Test Factory、start／stop、具体的Assert、正常・異常・境界・200件、テスト独立性の観点で再設計する。

本番クラス`CaseIndexService.cls`の処理は変更しない。非同期処理本体の方式設計はCP8、CalloutとMockの詳細はCP9で扱う。

## 2. 確定した対象と責務

### 2.1 変更対象

- `force-app/main/default/classes/CaseIndexService_Tests.cls`

### 2.2 テストクラスの責務

`CaseIndexService.groupOpenCasesByAccount()`が、入力されたCaseを契約どおりに抽出・グループ化して返すことを、独立したテストデータと具体的なAssertで証明する。

### 2.3 変更しない対象

- `force-app/main/default/classes/CaseIndexService.cls`
- `CaseIndexService`の既存業務契約

本番クラスとテストを同時に変更すると、失敗または品質変化の原因が本番コードかテストかを切り分けにくくなるため、CP5ではテストのみを再設計する。

`TestDataFactory`は今回利用したい既存メソッドがなく、新たに共通化する責務もないため、利用・変更しない。

## 3. テストデータの配置方針

### 3.1 `@TestSetup`

使用しない。対象メソッドはDBへ保存されたデータではなく、メモリ上で渡されたCaseを処理するため、共通の保存済みデータを準備する必要がない。

### 3.2 AccountId

Accountをinsertせず、テスト用Idを直接用意する。対象メソッドが必要とするのはAccountレコードそのものではなく、AccountIdがnullかどうか、および同じIdか異なるIdかという情報だからである。

グループの違いを表すIdは、Account Idとして扱える形式で、相互に異なる値を使用する。

`ACCOUNT_A_ID`と`ACCOUNT_B_ID`はクラス内の`static final`定数とする。staticな可変List、Map、Case等は保持しない。

### 3.3 `TestDataFactory`

使用・拡張しない。既存Factoryに今回利用するメソッドがなく、このテストクラスから新たに共通化すべき再利用責務も確定していないためである。

### 3.4 Case入力

各テスト固有の`List<Case>`は、そのテストメソッド内で作成する。入力条件と期待結果をテスト内で対応させる。

### 3.5 データ分離

`SeeAllData=false`とする。必要な入力は各テスト内で用意し、組織の通常業務データへ依存させない。

## 4. 正常・複数・順序・混在データのテスト契約

テスト用Account Idは`ACCOUNT_A_ID`と`ACCOUNT_B_ID`を使う。Caseはinsertせず、Idを持たない。

### 4.1 有効なCase 1件

- テスト名: `groupOpenCasesByAccount_withSingleValidCase_returnsGroupedMap`
- 入力: Subject=`Case A1`、Status=`New`、AccountId=`ACCOUNT_A_ID`
- 期待結果: Map 1キー、`ACCOUNT_A_ID`のList 1件、内容はCase A1

### 4.2 複数Account

- テスト名: `groupOpenCasesByAccount_withCasesForMultipleAccounts_returnsCasesGroupedByAccount`
- 入力:
  - Case A1: Status=`New`、AccountId=`ACCOUNT_A_ID`
  - Case B1: Status=`Working`、AccountId=`ACCOUNT_B_ID`
- 期待結果: Map 2キー、各キーのList 1件、各Caseが対応するAccountへ分類される
- Mapのキー順序は検証しない

### 4.3 同一Account内の入力順

- テスト名: `groupOpenCasesByAccount_withMultipleCasesForSameAccount_returnsCasesInInputOrder`
- 入力: 同じ`ACCOUNT_A_ID`を持つCase A2、A1、A3
- 期待結果: Map 1キー、List 3件、Subjectの順序はA2、A1、A3
- 意図: 名前順とは異なる入力にして、偶然の並べ替えではなく入力順維持を証明する

### 4.4 対象・対象外の混在

- テスト名: `groupOpenCasesByAccount_withValidAndExcludedCases_returnsOnlyValidCases`
- 入力:
  1. `New`、`ACCOUNT_A_ID`の`Case A Before Exclusions`
  2. null要素
  3. AccountIdがnullの`Case Without Account`
  4. Statusがnull、`ACCOUNT_A_ID`の`Case Without Status`
  5. `Closed`、`ACCOUNT_B_ID`の`Closed Case`
  6. `New`、`ACCOUNT_A_ID`の`Case A After Exclusions`
  7. `New`、`ACCOUNT_B_ID`の`Case B After Exclusions`
- 期待結果:
  - Mapサイズ2
  - Account A Listは`Case A Before Exclusions`、`Case A After Exclusions`の順で2件
  - Account B Listは`Case B After Exclusions`だけを1件
  - null、AccountIdなし、Statusなし、Closedは含まれない

対象外要素の後ろにも有効Caseを配置し、各`continue`後も処理が継続することを証明する。Closedと後続の有効Case Bは同じAccount Idを使い、B Listが1件であることからClosedが混入していないことも確認する。

### 4.5 Caseの識別と順序

未保存CaseはIdがnullであるため、`Subject`、`AccountId`、`Status`で内容を確認する。同じsObject参照であることは業務契約に含まれないため、必須Assertにしない。

Mapのキー順序は契約に含めず、必要なキーの存在を確認する。一方、各キーに対応する`List<Case>`では入力順を検証する。

## 5. 空入力・null・必須条件不足・Closedのテスト契約

### 5.1 null List

- テスト名: `groupOpenCasesByAccount_withNullInput_returnsEmptyMap`
- 入力: null
- 期待結果: 戻り値は非null、Mapサイズ0、キーなし、例外なし

### 5.2 空List

- テスト名: `groupOpenCasesByAccount_withEmptyInput_returnsEmptyMap`
- 入力: 空の`List<Case>`
- 期待結果: 戻り値は非null、Mapサイズ0、キーなし、例外なし

### 5.3 List内null

- テスト名: `groupOpenCasesByAccount_withNullElement_skipsNullAndProcessesFollowingCase`
- 入力: index 0がnull、index 1が`New`かつ`ACCOUNT_A_ID`を持つ`Valid After Null`
- 期待結果: Map 1キー、対象List 1件、内容は`Valid After Null`、例外なし
- 後続の有効Caseを結果まで確認し、null要素で処理全体が終了しないことを証明する

### 5.4 AccountIdなし

- テスト名: `groupOpenCasesByAccount_withCaseWithoutAccountId_excludesCase`
- 入力: AccountIdがnull、Status=`New`
- 期待結果: Mapサイズ0、キーなし、例外なし

### 5.5 Statusのblank境界

次の3条件は、失敗時に原因となった境界を特定できるよう個別テストにする。

- `groupOpenCasesByAccount_withNullStatus_excludesCase`: Statusがnull
- `groupOpenCasesByAccount_withEmptyStatus_excludesCase`: Statusが空文字
- `groupOpenCasesByAccount_withWhitespaceStatus_excludesCase`: Statusが空白文字だけ

いずれもAccountIdは`ACCOUNT_A_ID`とし、期待結果はMapサイズ0、キーなし、例外なしとする。

### 5.6 Closed

- テスト名: `groupOpenCasesByAccount_withClosedCase_excludesCase`
- 入力: AccountId=`ACCOUNT_A_ID`、Status=`Closed`
- 期待結果: Mapサイズ0、キーなし、例外なし

## 6. 200件境界・入力不変性・DBアクセスなし

次の3契約は、失敗時に原因を特定できるよう別テストにする。

### 6.1 200件一括処理

- テスト名: `groupOpenCasesByAccount_withTwoHundredValidCases_groupsAllCasesByAccount`
- Accountはinsertせず、`ACCOUNT_A_ID`と`ACCOUNT_B_ID`を使う
- 各Accountへ100件、合計200件を割り当てる
- Statusは全件`New`
- Subjectは`Case A-000`〜`Case A-099`、`Case B-000`〜`Case B-099`
- 入力はA、Bを交互に並べる
- 期待結果:
  - Mapサイズ2
  - 各List 100件、合計200件
  - 両Listを0〜99までループし、全件のSubject、AccountId、Statusを確認する
  - 各Account内の相対的な入力順を確認する
  - Mapのキー順序は確認しない

200件はServiceが拒否する固定上限ではなく、Trigger等の一括入力を想定した代表的なバルク境界である。201件で例外となる契約は設けない。

### 6.2 入力不変性

- テスト名: `groupOpenCasesByAccount_doesNotModifyInputListOrCases`
- 入力は、有効Case A、null、ClosedのCase B、有効Case Cの順とする
- 次を処理前後で確認する:
  - List件数
  - index順
  - nullの位置
  - Subject、Status、AccountId
  - 非null要素が元のCaseと同一参照であること

項目値が同じ別instanceへの置換も検出するため、参照同一性を`===`で確認する。公式Apex Developer Guideでは、`===`は同じメモリ位置を参照する場合にtrueとなるexact equality operatorである。

### 6.3 SOQL／DML 0回

- テスト名: `groupOpenCasesByAccount_withValidCases_executesWithoutSoqlOrDml`
- テスト用List作成後に`Test.startTest()`を呼ぶ
- 対象メソッドの直前と直後に以下を取得する:
  - `Limits.getQueries()`
  - `Limits.getDmlStatements()`
  - `Limits.getDmlRows()`
- after値は`Test.stopTest()`より前に取得する
- 期待差分はSOQL 0、DML文0、DML行0

## 7. Assertと共通helper

### 7.1 Assert順序

1. 戻り値がnullでない
2. Mapサイズ
3. 必要なキーが存在する
4. 不要なキーが存在しない
5. キーに対応するListがnullでない
6. List件数
7. 各indexのCase
8. CaseのAccountId、Subject、Status

キー存在とList非nullを先に確認し、`result.get(key).size()`等による二次的なNullPointerExceptionを避ける。

### 7.2 message

200件ループと共通helperの項目Assertには、次を含める。

- expectedAccountId
- List内index
- 検証対象項目
- 期待値
- 実測値

SOQLとDMLは、対象メソッドがそのリソースを消費してはいけない契約をmessageに示す。DML行差分の完全なmessageは`groupOpenCasesByAccount must not consume any DML rows.`とする。

### 7.3 `assertCasesForAccount`

- 可視性・修飾子: `private static`
- 引数:
  - 実測`Map<Id, List<Case>>`
  - `Id expectedAccountId`
  - `List<Case> expectedCases`
- 担当するAssert:
  1. 期待Account Idのキーが存在する
  2. 対応Listがnullでない
  3. List件数が一致する
  4. 各indexの順序が一致する
  5. AccountIdが一致する
  6. Subjectが一致する
  7. Statusが一致する
- 担当しないAssert:
  - Map全体の非null・サイズ
  - 不要キー
  - 入力不変性
  - SOQL／DML差分
  - その他のテスト固有契約

### 7.4 空Map

サイズ0に加え、戻り値自体がnullではないことを確認する。

## 8. テスト独立性と既存テストからの移行

### 8.1 独立性

- staticな可変状態は使用しない
- 共有するのは2つの`static final Id`定数だけとする
- 各テストのListとCaseは各テストメソッド内で作成する
- 他テストのList、Case、DBデータを再利用しない
- 各テストが独立した入力と結果を持ち、実行順へ依存しない

### 8.2 既存7テストの移行

- `ValidCases_ReturnsGroupedMap`: 正常1件と複数Accountへ分割
- `MultipleCasesSameAccount_MaintainsInputOrder`: `withMultipleCasesForSameAccount_returnsCasesInInputOrder`へ改名
- `NullInput_ReturnEmptyMap`: `withNullInput_returnsEmptyMap`へ改名
- `NullElementInList_SkipsNullAndReturnsMap`: `withNullElement_skipsNullAndProcessesFollowingCase`へ改名
- `EmptyInput_ReturnEmptyMap`: `withEmptyInput_returnsEmptyMap`へ改名
- `NullRequiredFields_ExcludesFromMap`: AccountIdなし、Status null、空文字、空白文字へ分割
- `MixedCases_ReturnsOnlyValidCases`: Closed単独と新しい混在入力へ分割

旧メソッド名は残さない。

### 8.3 最終テスト構成

- 正常・グループ化・順序・混在: 4件
- null・空・除外境界: 8件
- 200件・入力不変性・SOQL／DML: 3件
- 合計: 15件

同名テスト、完全に同じ入力と期待結果、同一契約だけを重複確認するテストはない。一部条件は単独契約と混在時の処理継続という異なる目的で登場する。

## 9. 代替案比較

### 9.1 テスト用Id対Account insert

- テスト用Id: DMLを消費しないが、参照先がDBに存在しないためCaseをinsertするテストには使えない
- Account insert: 保存可能な参照先を用意できるが、DML制限と周辺自動化の影響を受ける
- 採用: 今回はメモリ処理だけなのでテスト用Idを使う。Case保存や参照先を必要とするDML処理へ変わればAccountをinsertする

### 9.2 各テスト内データ対`@TestSetup`

- 各テスト内: 入力と意図が近く、固有状態を明示できるが、作成記述が増える
- `@TestSetup`: 共通の保存済みデータを再利用できるが、各テストで異なるメモリ入力には適合しにくい
- 採用: 各テスト内で作る。同じDBデータを使うテストが増えた場合に`@TestSetup`を再検討する

### 9.3 Case直接作成対`TestDataFactory`

- 直接作成: テスト固有のCase状態が見えるが、記述が繰り返される
- Factory: 汎用性の高い生成を再利用できるが、今回の単純な入力を汎用化すると引数・分岐が増え、テスト意図を隠す
- 採用: 直接作成。2か所以上で汎用性の高い生成処理が生じた場合にFactoryへの移動を検討する

### 9.4 helper対直接Assert

- helper: 共通検証の一貫性を保てるが、呼出し箇所だけでは詳細が見えにくい
- 直接Assert: テスト内で完結するが、反復とコード量が増える
- 採用: `assertCasesForAccount`にはAccount別Listの共通検証だけを持たせる。Map全体、Limits、入力不変性、テスト固有Assertは各テストに残し、helperへ固有分岐を追加しない

### 9.5 品質契約3テスト対1テスト統合

- 3テスト: 200件、入力不変性、Limitsの失敗原因が明確だが、テスト数と記述は増える
- 1テスト: メソッド数は減るが責務が混在し、診断と保守性が低下する
- 採用: テスト責務と失敗原因を明確にするため3テストへ分ける

## 10. 設計状態

Gate Bの8項目は本人説明により確定した。Gate Cでは本人が本書に基づいて`CaseIndexService_Tests.cls`を実装する。

本書は本人説明を統合した詳細設計であり、実装、コンパイル、テスト実行、デプロイ、静的解析の証拠を代替しない。

## 11. 未完了事項

- Gate C: 本人実装と自己確認
- Gate D: レビュー修正、API 67.0デプロイ、対象15テストと関連全テスト、静的解析、証拠監査
- 本人振り返り、commit、push、Pull Request、review、merge
