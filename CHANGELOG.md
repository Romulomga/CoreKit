# Changelog

## 0.1.7 - 2026-11-17

- `CoreKitNavigation`: cada destino diz como aparece (`presentation`, novo em `NavigableDestination`: `.push` por
  padrão, ou `.sheet`/`.fullScreenCover`). `Coordinator.navigate(to:)` sem `type` usa o dele, e `Navigator.open(_:)`
  também: um deep link abre o editor como folha, do jeito que o app abre. Um `type` explícito continua valendo.

## 0.1.6 - 2026-11-17

- `CoreKitNavigation`: `Navigator`, a navegação inteira do app num objeto só, gêmeo do `Navigator` do CoreKit-Android.
  Tem a pilha de baixo (`root`: a entrada de um app com login, embaixo da cover das abas) e uma pilha por aba ou seção
  da barra lateral, criada na primeira vez que é pedida. Cada destino diz onde mora (`tab`, novo em
  `NavigableDestination`, `nil` por padrão = pilha de baixo), e `open(_:)` leva um destino, ou uma URL de um
  `DeepLinkDestination` (`init?(url:)`), à pilha certa: troca de aba, a própria aba volta à raiz, a tela que já está no
  topo fica, `replacesStack` troca a pilha, o resto empilha; uma folha aberta na aba fecha antes. `holdLinks(until:)`
  segura os links de aba até o app estar pronto (observa a condição) e `discardHeldLink()` os descarta no fim da
  sessão. `NavigationTab` monta uma aba (host, tag e ícone) e `TabNavigationRoot(navigator)` as abas, com o navigator
  no ambiente. `SessionObserver(navigator:)` zera as abas depois do logout, com a cover já fechada. Tudo acréscimo: o
  `Coordinator`, o `NavigationHost` e o `TabNavigation` avulsos continuam.

## 0.1.5 - 2026-11-17

- `CoreKitTesting`: o `eventually` conta voltas em vez de olhar o relógio. Cada volta cede o main actor uma vez e dorme
  10 ms; o `timeout` compra `timeout / 10 ms` voltas (com o main actor livre, desiste depois de mais ou menos
  `timeout`, como antes). Com o prazo de relógio de 2 s, o teste falhava ao acaso quando as suítes `@MainActor`
  rodavam em paralelo: a espera ficava segundos sem vez no main actor e, quando voltava, o prazo tinha passado, com o
  valor já na fila. Novo parâmetro `ceiling` (30 s por padrão), só como rede de segurança. A assinatura antiga
  continua valendo.

## 0.1.4 - 2026-11-16

- `CoreKit`: `AsyncStream.observing { leitura }`, o valor que a leitura devolve agora e de novo a cada mudança
  observável que ela tocou, descartando repetidos e parando quando quem escuta sai. É o fluxo de valores do padrão de
  arquitetura dos apps: a ViewModel transforma os objetos do banco em valores dentro da leitura, e o store faz cada
  gravação contar lendo o próprio contador ali dentro. Saiu do Minha Micro Área. Só iOS (no Android, o `Flow` do Room
  com `stateInScreen`).
- `CoreKitTesting`: `eventually`, para conferir o que chega à ViewModel pelo fluxo (`#expect(await eventually { ... })`),
  e `ArchitectureCheck`/`ArchitectureRule`, para o teste de arquitetura de cada app (regras por arquivo e padrão,
  pastas proibidas e os nomes dos `@Model` lidos do código). Só iOS por enquanto.

## 0.1.3 - 2026-11-16

- `CoreKit`: `onFirstAppear` assíncrono, para a carga inicial da tela. O `.task { await viewModel.load() }` carregava
  de novo a cada volta à tela; aqui roda uma vez por entrada na pilha. Sair antes de terminar cancela a carga, e a
  próxima aparição roda de novo. Gêmeo do `LaunchedOnce` do CoreKit-Android.

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
