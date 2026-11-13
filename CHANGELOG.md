# Changelog

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
