# CoreKit

Base não visual dos apps iOS do Rômulo: as peças que os apps copiavam um do outro (analytics e setup do Firebase, a
loja do StoreKit 2, o pedido de avaliação, o banco que não abre, a navegação do Homer) e cujas cópias já tinham
divergido. Gêmeo por conceito do [CoreKit-Android](https://github.com/Romulomga/CoreKit-Android); o par visual é o
[DSKit](https://github.com/Romulomga/DSKit).

## Módulos

Cada módulo é uma biblioteca do pacote, e o app só compila as que importa. O SwiftPM baixa todas as dependências
declaradas (Firebase, Mixpanel), mas só compila as dos módulos usados.

- `CoreKit`: `onFirstAppear`, `AsyncStream.map`.
- `CoreKitNavigation`: `Coordinator` (push, sheet, tela cheia; empilhar o destino que já está no topo não faz nada),
  `NavigationHost`, `RouteLink` (linha com o chevron nativo que passa pelas regras do coordinator),
  `TabNavigation`/`TabNavigationRoot`, `ReloadNotifier`/`onReload`, `SessionObserver` (destinos
  `SessionDestination`), `NavigationDiagnostics`.
- `CoreKitAnalytics`: `Analytics.start(engines:policy:)`, `Analytics.shared` (repassa a todos os motores),
  `AnalyticsClient`, `AnalyticsValue`, `CollectionPolicy.storeBuildsOnly` (debug nunca coleta, salvo com
  `--analytics-debug`; `--uitests` nunca), `trackScreen`.
- `CoreKitFirebase`: motor `.firebase(options:)`, Analytics + Crashlytics sem IDFA. Não configura o Firebase de novo
  se o app já configurou.
- `CoreKitMixpanel`: motor `.mixpanel(token:)`.
- `CoreKitStore`: `ProStore` (StoreKit 2) com `EntitlementState` (`unknown`/`free`/`pro`), o último direito
  confirmado guardado em `EntitlementMemory`, catálogo com falha parcial, `restore` que diz se a loja confirmou.
- `CoreKitReview`: `ReviewGate` (uma vez por versão, intervalo opcional) e `reviewRequest(for:gate:)`.
- `CoreKitPersistence`: `PersistentStore.open` devolve `.healthy` ou `.degraded`, nunca derruba o launch e nunca
  apaga o arquivo; `locationIsReachable` para o "Verificar de novo".
- `CoreKitTesting`: `RecordingAnalyticsClient`, `FakeStoreGateway`, `FakeEntitlementMemory`.

Só no iOS: `SessionObserver`, `ReloadNotifier`, `NavigationDiagnostics`, a barra de abas escondida no push, a
validade da assinatura dentro de `EntitlementKind`.

## Uso num app

```yaml
# project.yml (XcodeGen)
packages:
  CoreKit:
    url: https://github.com/Romulomga/CoreKit
    minorVersion: 0.1.0

targets:
  App:
    dependencies:
      - package: CoreKit
        product: CoreKitNavigation
      - package: CoreKit
        product: CoreKitFirebase
```

```swift
Analytics.start(engines: [.firebase()], policy: .storeBuildsOnly)
```

O que fica em cada app: nomes de evento, ids de produto, chaves dos motores, o enum de destinos, quando pedir
avaliação e a tela de recuperação do banco. No `project.yml` do app continuam `-ObjC` e o script de dSYM do
Crashlytics.

## Verificar

```sh
xcodebuild -scheme CoreKit-Package -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Licença MIT.
