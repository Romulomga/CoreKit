# Changelog

## 0.1.2 - 2026-11-15

- `CoreKit`: `SingleFlight` e `KeyedSingleFlight`, gêmeos dos do CoreKit-Android. A trava fecha antes de qualquer
  `await` e abre quando a ação termina, falha ou é cancelada; `launch` devolve a `Task` (ou `nil` quando o toque foi
  ignorado) e `run` roda na task de quem chama. Os apps tinham cada um o seu `isSaving`/`isRestoring`.
- `CoreKitFirebase`: os parâmetros do `screen_view`, do `purchase` e dos eventos, e a escolha do plist, saem para
  funções puras internas, testadas em `CoreKitFirebaseTests` sem o Firebase configurado. Nada muda na API pública nem
  no que vai para o Firebase.

## 0.1.1 - 2026-11-14

- `CoreKitStore`: `StoreTransaction.priceCents`, o preço cobrado em centavos com o mesmo arredondamento de
  `ProProduct.priceCents` (o Canetto e o MagicPick repetiam a conta).
- `CoreKitPersistence`: `ForcedFailure` ganha `init()` público, para previews da tela de recuperação; o log de falha
  usa o subsystem do app (o bundle id), como o analytics, em vez de "CoreKit".
- `CoreKitMixpanel`: `.mixpanel(token:flushInterval:)`, para um build de homolog rastreado pelo QA.
- `CoreKitTesting`: sai o `FakeEntitlement`, que nenhum app nem teste usava.

## 0.1.0 - 2026-11-13

- `CoreKit`: `onFirstAppear`, `AsyncStream.map`.
- `CoreKitNavigation`: a camada de navegação do Homer, generalizada (`mainTab` só para `SessionDestination`, padrões
  para `isStandalone`/`presentationDetent`/`routeName`, `tint` opcional) e com a regra do CoreKit-Android: empilhar o
  destino que já está no topo não faz nada. `RouteLink` empilha com a aparência do `NavigationLink` e passa pelas
  mesmas regras.
- `CoreKitAnalytics`, `CoreKitFirebase`, `CoreKitMixpanel`: cliente com fan-out para os motores, política de coleta
  gêmea da `CollectionPolicy` do Android, `trackScreen`.
- `CoreKitStore`: `ProStore` sobre StoreKit 2, unindo as correções das cópias do ReciboJa e do Canetto.
- `CoreKitReview`: `ReviewGate` e o ponto de pedido em SwiftUI.
- `CoreKitPersistence`: `PersistentStore.open` saudável/degradado e `locationIsReachable`.
- `CoreKitTesting`: fakes de analytics e de compras.
