# Changelog

## 0.1.13 - 2026-11-17

- `CoreKitSync` (novo módulo): o sync de um assunto offline-first. `SyncSubject` (o que o app implementa: `pull(since:)`
  devolve um `PullBatch`, de mudanças ou a lista inteira, paginado por `hasMore`; `apply(_:keeping:state:)` grava dados
  e `SyncState` num save só; `push(_:)` devolve `PushOutcome`), `Outbox` e `PendingChange` (a fila, tabela do app, com
  id gerado no aparelho como chave de idempotência e lápide para remoção), `SyncEngine` (um sync por vez, quem chama
  junto espera a mesma rodada; envia antes de ler; uma falha no caminho para a rodada, conta a tentativa e agenda outra
  com `SyncRetry`; uma recusa segura as mudanças seguintes do registro até o app resolver; com `ConflictPolicy`
  `.pendingWins`, o padrão, a leitura não toca no registro com envio esperando, com `.serverWins` o servidor
  substitui e a fila do registro sai; `syncIfStale`, `pushPending`, `follow(connectivity:)`; `SyncStatus` observável;
  `reset()` no logout) e `BackgroundSync` (sobre `BGTaskScheduler`, atrás de `BackgroundScheduling`; confere
  `UIBackgroundModes` `fetch` e `BGTaskSchedulerPermittedIdentifiers` antes de registrar, agenda a próxima a cada
  rodada e cancela a que o sistema toma de volta). Gêmeo do módulo `sync` do CoreKit-Android 0.1.12. O envio só foi
  provado contra dublês: o primeiro app com servidor é o primeiro uso real.

## 0.1.12 - 2026-11-17

- `CoreKit`: blocos de cache para o assunto "online" (o dado é do servidor e só faz sentido com ele), vindos do Homer e
  generalizados: `KeyedResource` (um valor por chave: carga idempotente, quem chama junto espera a mesma busca, a busca
  sobrevive à tela, gravação e fim de sessão descartam a resposta velha), `PagedResource` (listas paginadas, sem
  repetidos, nenhuma próxima página durante um reinício), `Loadable`/`LoadStatus`, `SingleKey`, `CacheRead`,
  `SessionCache` com `values(_:)` e `SessionCaches` (o logout esvazia todos). A falha agora é do app: cada bloco recebe
  `mapError: (any Error) -> Failure?`, e `nil` diz que foi um cancelamento da camada de rede do app, que nunca vira
  falha. Gêmeos dos blocos do `core` do CoreKit-Android 0.1.11.
- Os testes do módulo `CoreKit` passam a usar o `CoreKitTesting` (`eventually`).

## 0.1.11 - 2026-11-17

- `CoreKitAnalytics`: `AnalyticsClient.setUserID(_:)` (quem usa o app, num app com conta; `nil` no logout),
  `setCrashKey(_:forKey:)` e `addBreadcrumb(_:)` (o que vai no próximo relatório de falha). Requisitos com implementação
  vazia por padrão: acréscimo, nada quebra. O hub guarda o último id e o entrega quando os motores começam ou a coleta
  volta a ser ligada, porque o app pode restaurar a sessão antes do `start` ou com a chave desligada. Nunca e-mail, nome
  ou telefone: um id opaco do servidor do app.
- `CoreKitFirebase`: user ID no Analytics e no Crashlytics, chaves e trilha no Crashlytics.
- `CoreKitMixpanel`: `identify` com o id e `reset` no logout. Agora gêmeo do módulo `mixpanel` do CoreKit-Android 0.1.10.
- `CoreKitTesting`: `RecordingAnalyticsClient` registra `userIDs`, `crashKeys` e `breadcrumbs`.

## 0.1.10 - 2026-11-17

Portas abertas pela regra nova (o que um app qualquer precisaria), todas com o comportamento de antes como padrão:

- `CoreKitAnalytics`: `CollectionPolicy` ganhou `init(debugBuildsCollect:debugArgument:automationArguments:)`; antes
  só existia `.storeBuildsOnly`, com os argumentos fixos.
- `CoreKitNavigation`: `NavigationDiagnostics.addObserver(_:)`/`removeObserver(_:)`, para mais de um ouvinte (analytics e
  um crash reporter); `observe(_:)` continua trocando o principal.
- `CoreKitStore`: `ProStore.purchase(_:appAccountToken:)` liga a compra à conta do app (o servidor a recebe nas App Store
  Server Notifications); `StoreGateway` ganhou o requisito com implementação padrão que ignora o token, e o
  `FakeStoreGateway` registra `purchaseAccountTokens`. `ProStore(productOrder:)`: `.byPrice` (padrão) ou `.asPlanned`.
- `CoreKitReview`: `ReviewGate` com chaves padrão (`corekit.review.lastPromptVersion`/`lastPromptDate`) para app novo.
- `CoreKitPersistence`: `PersistentStore.open(…, cloudKitDatabase:)`; `.automatic` (o padrão do SwiftData, que já era o
  usado) sincroniza quando o app tem o iCloud, `.none` nunca, `.private(_:)` nomeia o contêiner.

Correção:

- `CoreKitStore`: assinante no período de carência da cobrança perdia o Pro. Com o "Billing Grace Period" ligado, a Apple
  mantém o direito enquanto tenta cobrar de novo, e o `currentEntitlements` lista a transação com a validade já vencida;
  o resolvedor exigia validade futura. `StoreTransaction.gracePeriodExpirationDate` (lido do status da assinatura só
  quando a validade já passou) e `entitledUntil` entram na regra; o direito lembrado vence no fim da carência.

## 0.1.9 - 2026-11-17

- `CoreKitNetwork` (novo produto): o `NetworkKit` do Homer, generalizado para qualquer app com servidor. Mesmo
  comportamento e os mesmos 174 testes, arrumado antes de entrar: pastas por assunto (`Request/`, `Auth/`, `Retry/`,
  `Connectivity/`, `Logging/`, `Errors/`), `NetworkServiceProtocol` renomeado para `NetworkServing`, comentários em
  inglês. Toda a API pública ficou. O que era fixo virou parâmetro do `NetworkService`, com o valor de antes como padrão:
  `requestTimeout`/`resourceTimeout` (40 e 60 s; o tempo da requisição agora vale também no `URLRequest`, que antes
  ficava sempre em 40), `interceptors` do app (rodam depois da autenticação e antes do log), `logger` do app,
  `redactedHeaders` (o `headerKey` do token é sempre mascarado, qualquer que seja o nome) e `urlRedaction`.
- `URLRedaction` (gêmeo do `UrlRedaction` do CoreKit-Android): o espelho do log de debug no log do sistema leva a URL
  sem query, sem fragmento e sem os trechos de caminho que o app marca como dado digitado.
- Regra nova no `CLAUDE.md`: API pública e pontos de extensão se avaliam pelo que um app qualquer precisaria, não pelo
  que os apps de hoje usam.

## 0.1.8 - 2026-11-17

- `CoreKitAnalytics`: a chave do usuário ("Enviar estatísticas" nos Ajustes), `Analytics.setCollectionEnabled(_:)`,
  vale para todos os motores de uma vez. Chamada antes do `start` com a escolha salva: desligada, nenhum motor é
  configurado e nada sai do aparelho, nem os eventos da abertura; ligada depois, os motores começam ali; desligada com
  os motores rodando, cada um desliga a coleta do seu SDK (Firebase Analytics + Crashlytics, opt-out do Mixpanel) e
  nada mais é repassado; ligada de novo, voltam sem ser configurados outra vez. A política do build continua mandando:
  build de debug nunca coleta. `AnalyticsEngine` ganha `setCollectionEnabled` (padrão: nada) e `AnalyticsClient` o
  requisito `setCollectionEnabled(_:)` com implementação vazia por padrão: acréscimo, nada quebra.
- `CoreKitAnalytics`: `recordError` pelo `Analytics.shared` leva só o domínio e o código do erro; a mensagem e o resto
  do `userInfo` (que podem citar o que o usuário digitou) ficam no aparelho.
- `CoreKitMixpanel`: ao começar, desfaz um opt-out que ficou de uma abertura anterior (o Mixpanel o guarda no
  aparelho), como o Firebase já fazia com a coleta.
- `CoreKitTesting`: `RecordingAnalyticsClient` registra a chave (`collectionChanges`, `collectionEnabled`).

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
