# CP6 AccountUpdateServiceを設計した流れ

- 記録日：2026-11-06
- 対象：[AccountUpdateService.cls](../force-app/main/default/classes/AccountUpdateService.cls)
- 実装契約：[CP6 Security Recipes 詳細設計書・第5章](CP6_SECURITY_RECIPES_DESIGN.md#5-accountupdateservice-詳細設計)
- 記録元：ユーザーが提示した設計経緯と、2026-11-05にレビューした実装

要件から処理段階を分け、呼出元が必要とする情報からDTOとメソッドの構成を決めた経緯を残す。本書は設計の経緯を説明し、実装・テストの成否は[検証サマリー](../evidence/README.md#cp6-security-recipes)に示す。

## 1. 要件を処理単位に分解した

外部から渡された複数のAccount更新候補について、次を実現する要件だった。

- 実行ユーザーが更新できる項目だけを更新する。
- FLSによって除去された項目を呼出元へ返す。
- 入力Accountごとの成功・失敗を呼出元へ返す。
- レコード単位のDML失敗があっても、他の有効なAccountは更新する。
- SOQLやDMLをループ内で実行しない。
- 呼出元のListとAccountを変更しない。

この要件から処理を次の段階に分けた。

```text
入力検証 → FLSによる項目除去 → 部分成功DML → DML結果の変換 → Responseの返却
```

## 2. 入力値は信頼しない方針にした

入力は`List<Account> accounts`とした。ただし、Listの内容が正しいとは限らないため、DML前に入力全体の構造を検証する。

- List自体がnull。
- List内にnullがある。
- `Account.Id`がnull。
- IdがAccount以外のオブジェクトに属する。
- 同じAccount Idが重複している。

構造不正はリクエストの組み立て自体の問題として、`IllegalArgumentException`でリクエスト全体を拒否する。全件の構造検証が終わるまで、FLS除去やDMLには進まない。

重複Idでは最初と重複した入力位置を通知するため、`Map<Id, Integer> firstInputIndexById`を使用する。これにより、例外メッセージへ`firstInputIndex`と`duplicateInputIndex`を含められる。

空Listは不正入力にせず、DMLを実行せずに空のResponseを返す契約とした。

## 3. 更新可能な項目だけを残す方法を考えた

更新不可項目を除去するため、次のAPIを採用した。

```apex
Security.stripInaccessible(
    System.AccessType.UPDATABLE,
    accounts,
    true
)
```

`enforceRootObjectCRUD = true`とした理由は、Accountの更新CRUDがない場合、項目を除去して更新処理を継続せず、全体を例外で失敗させるためである。期待する例外型は`System.NoAccessException`とし、Updateの権限テストで実測確認する。

stripの結果から、後続処理には次の2種類の情報が必要になった。

- 更新可能な項目だけを持つAccount List。
- リクエスト全体でFLSにより除去されたAccount項目名。

この2つをまとめて返す内部処理用の`AccountUpdatePreparation`を作成した。

```text
AccountUpdatePreparation
├─ sanitizedAccounts
└─ removedFields
```

Service内部だけで使用するため、private内側クラスとした。`getRemovedFields()`にAccountキーがなければ、`removedFields`は非nullの空Setにする。

## 4. 入力Accountを直接DMLしない設計にした

元入力を直接DMLへ渡さず、`SObjectAccessDecision.getRecords()`から取得した`sanitizedAccounts`をDMLへ渡す。

`getRecords()`は、元入力を基に更新不可項目を除いた新しいsObjectのListを返す。この仕組みを使うため、明示的な`clone()`は採用しない。[公式仕様：SObjectAccessDecision](https://developer.salesforce.com/docs/platform/apex-ref/references/apex-ref/apex-class-system-sobjectaccessdecision.html)

元入力は結果のIdやindexを取得するために保持する。入力Listの件数・順序・要素参照と、各AccountのId・項目値が変わらないことは、入力不変性テストで確認する。

## 5. 部分成功DMLを選択した

一部のAccountがレコード単位で失敗しても、他の有効なAccountを更新する必要があった。そのためDMLキーワードではなく`Database.update`を使い、部分成功を指定した。

```text
Database.update
├─ allOrNothing = false
└─ accessLevel = USER_MODE
```

USER_MODEを明示し、CRUD・FLS・共有を実行ユーザー基準で適用する。stripは項目を除去するために使い、後続DMLでの共有アクセスや入力値などの失敗は別に扱う。

DMLはループ外で最大1回とする。空入力、構造検証の例外、DML前のCRUD例外では実行しない。Service自身はSOQLを実行しない。

部分成功の対象はレコード単位で扱える失敗であり、ガバナ制限超過などのトランザクション全体の失敗まで成功結果として返す契約ではない。

## 6. SaveResultと元入力を対応付けた

`Database.update()`の戻り値は`Database.SaveResult[]`であり、成功可否、Id、失敗時の`Database.Error[]`を取得できる。

stripは項目を除去するが入力レコード自体を間引かず、入力順を維持する。SaveResultもDML入力の順序に対応するため、次の関係を維持できる。[公式仕様：SaveResult](https://developer.salesforce.com/docs/platform/apex-ref/references/apex-ref/apex-methods-system-database-saveresult.html)

```text
accounts[i]
    ↓
sanitizedAccounts[i]
    ↓
saveResults[i]
    ↓
results[i]
```

この契約から、各結果に`inputIndex`を持たせることにした。

結果の`accountId`には、成功・失敗とも元入力の`accounts[i].Id`を設定する。どの入力の結果かを常に同じ方法で特定でき、`SaveResult.getId()`がnullとなる失敗でも元入力Idを保持できるためである。

当初の説明にあった「失敗したSaveResult.getId()は常にnull」は訂正する。公式仕様ではAPI 53.0以降は更新対象のIdを返し、更新時のレコードロック失敗ではnullになる。元入力Idを使う契約は、この挙動に依存しない。[公式仕様：getId()](https://developer.salesforce.com/docs/platform/apex-ref/references/apex-ref/apex-methods-system-database-saveresult.html)

## 7. 入力ごとの結果クラスを考えた

呼出元が入力ごとの結果を確認できるように、`AccountUpdateItemResult`を作成した。

```text
AccountUpdateItemResult
├─ inputIndex
├─ accountId
├─ success
└─ errors
```

Serviceが正常にreturnした場合、次を保証する。

```text
response.results.size() == accounts.size()
response.results[i].inputIndex == i
response.results[i]はaccounts[i]の結果
response.results[i].accountId == accounts[i].Id
```

成功時は`success = true`と非nullの空errorsを設定する。失敗時は`success = false`と全Database.Errorの変換結果を設定する。

例外で処理全体が終了した場合はResponseを返さないため、この結果件数・順序の保証の対象外とする。

## 8. DMLエラーを独自DTOへ変換した

`Database.Error`から取得できる次の情報を、`AccountUpdateError`として呼出元へ返す。

| DTO項目 | 取得元 |
| --- | --- |
| `statusCode` | `getStatusCode()` |
| `message` | `getMessage()` |
| `fields` | `getFields()` |

1つのSaveResultに複数のエラーがある場合、すべてを個別のAccountUpdateErrorへ変換する。

```text
AccountUpdateItemResult：入力1件に対して1件
└─ errors
   ├─ AccountUpdateError：1件目
   └─ AccountUpdateError：2件目
```

エラー数にかかわらず、AccountUpdateItemResultは入力1件につき1件だけ作成する。

## 9. 最終Responseを考えた

呼出元が確認したい情報は、リクエスト全体で除去された項目と、入力Accountごとの処理結果の2種類だった。そのため最終戻り値としてAccountUpdateResponseを作成した。

```text
AccountUpdateResponse
├─ removedFields
└─ results
   └─ List<AccountUpdateItemResult>
```

`removedFields`はリクエスト全体のAccount項目名を集約したSetであり、入力ごとの除去履歴ではない。入力ごとの成功・失敗は`results`で確認する。

`success = true`は除去後Accountの更新成功を意味し、元入力の全項目が適用されたことは意味しない。適用されなかった項目は`removedFields`から別途確認する。

`removedFields`と`results`は常に非nullとし、空入力では空Setと空Listを持つResponseを返す。

## 10. DTOをpublic内側クラスにした

次のDTOはAccountUpdateService専用であり、他のServiceで利用する要件がないため、独立クラスではなくpublic内側クラスとした。

- `AccountUpdateResponse`
- `AccountUpdateItemResult`
- `AccountUpdateError`

呼出元は`AccountUpdateService.AccountUpdateResponse`のように型名を指定できる。

値の保持にはpublic変数ではなく、次のプロパティを使用した。

```apex
public Boolean success { get; private set; }
```

ServiceはDTOのconstructorへ必要な値をまとめて渡し、呼出元は値を読み取れるがプロパティを再代入できない形とした。

ただし、`List`や`Set`のプロパティは、その中身まで変更不可になるわけではない。今回のDTOはコレクションの完全な不変性を保証するものではない。

Serviceが返すDTOの非null・件数・順序の保証と、呼出元がpublic constructorで任意に作成するDTOは区別する。現実装のconstructor自体は、渡された値の追加検証や防御的コピーを行わない。

## 11. メソッドを責務ごとに分けた

処理を次のprivate staticメソッドへ分けた。

| メソッド | 責務 |
| --- | --- |
| `validateUpdateCandidates` | 入力構造を検証する |
| `prepareUpdatableAccounts` | FLSを適用し、除去後Accountと除去項目を返す |
| `executePartialUpdate` | USER_MODEで部分成功DMLを1回実行する |
| `convertSaveResults` | SaveResultを入力ごとのDTOへ変換する |

public staticメソッドの`updateAccountsWithUpdatableFields`は、これらを順番に呼び出して最終Responseを返す進行役とした。

実装では本体を`public with sharing`、constructorをprivateとし、instance状態を持たない構成を採用した。

## 12. 最終的な処理の流れ

```text
updateAccountsWithUpdatableFields(accounts)
    ↓
validateUpdateCandidates(accounts)
    ↓
空Listなら空Response
    ↓
prepareUpdatableAccounts(accounts)
├─ sanitizedAccounts
└─ removedFields
    ↓
executePartialUpdate(sanitizedAccounts)
└─ Database.SaveResult[]
    ↓
convertSaveResults(saveResults, accounts)
└─ List<AccountUpdateItemResult>
    ↓
new AccountUpdateResponse(removedFields, results)
    ↓
呼出元へ返却
```

今回の設計では「呼出元が最終的に何を確認したいか」から必要な情報を洗い出し、SalesforceのAPIが返す値からどう組み立てるかを考えることで、DTOとメソッドの構成を決めた。

## 最終検証

Updateの17テストで、入力検証、CRUD・FLS・共有不足、部分成功、入力不変性、200件一括更新を確認した。API 67.0での実デプロイと回帰テストの結果は、[CP6検証サマリー](../evidence/README.md#cp6-security-recipes)に掲載する。
