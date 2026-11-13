# CLAUDE.md — ELEMENTS

Diretrizes do projeto para o Claude Code. Leia este arquivo antes de qualquer tarefa.

## 1. Visão geral

**ELEMENTS** é um jogo indie 2D side-scrolling, estilo Metroidvania, em pixel art, com exploração, combate e progressão de habilidades.

Universo de fantasia elemental original com quatro protagonistas:

| Elemento | Personagem |
|----------|------------|
| Água     | Aqua       |
| Fogo     | Ignis      |
| Terra    | Terra      |
| Ar       | Aeris      |

Cada protagonista tem habilidades próprias, atributos, estilo de combate e árvore de evolução.

## 2. Stack técnica

- **Engine:** Godot **4.7.2 Stable**, edição Standard (não .NET)
- **Linguagem:** GDScript — sem C#, sem GDExtension, sem bibliotecas nativas
- **Renderizador:** Compatibility (OpenGL ES 3 / WebGL 2)
- **Plataforma prioritária:** Web (HTML5 / WebAssembly), publicada no **itch.io** como jogo incorporado à página
- **Plataforma secundária futura:** Windows — manter compatibilidade sem comprometer a Web
- **Resolução de referência:** 1280x720
- **Visual:** Pixel Art, 2D side-scrolling
- **Modo:** single-player

## 2.1. Compatibilidade Web (obrigatório)

Toda decisão técnica deve funcionar na exportação Web. Regras:

1. **Todo código deve ser compatível com exportação Web.** Nenhum recurso exclusivo de desktop.
2. **Exportação Web sem suporte a threads** (`Thread Support` desligado). Dispensa os headers COOP/COEP (SharedArrayBuffer) e funciona no itch.io sem configuração extra.
   - Não usar `Thread`, `Mutex`, `Semaphore` nem `WorkerThreadPool`.
   - Não depender de `ResourceLoader.load_threaded_request` para paralelismo real.
3. **Nada bloqueante:** evitar loops longos num único frame e carregamentos pesados síncronos. Dividir o trabalho em vários frames quando necessário; preferir `preload` para recursos pequenos e frequentes.
4. **Sistema de arquivos:** usar apenas `res://` (leitura) e `user://` (escrita). Na Web, `user://` é persistido no **IndexedDB** do navegador. Nunca usar caminhos absolutos, `OS.execute`, `OS.shell_open` para arquivos ou diálogos nativos de arquivo.
5. **Save:** projetado para `user://` com dados pequenos e serializáveis (ex.: JSON ou `ConfigFile`). Considerar que o jogador pode limpar os dados do navegador e que o modo anônimo pode não persistir. O formato concreto será proposto e confirmado antes de implementar.
6. **Entrada no navegador:**
   - Evitar atalhos que o navegador captura (ex.: `Ctrl+W`, `Ctrl+T`, `Ctrl+N`, `F5`, `F11`, `Ctrl+R`). `Esc` sai da tela cheia/pointer lock.
   - O iframe precisa de foco (clique) para receber teclado.
   - Gamepads só são detectados após o jogador pressionar um botão; o mapeamento pode variar por navegador.
   - Tela cheia e captura de mouse só funcionam em resposta a uma ação do usuário.
7. **Áudio:** navegadores bloqueiam áudio até a primeira interação do usuário — prever uma tela inicial com "clique/pressione para começar".
8. **Desempenho e tamanho:** otimizar texturas (spritesheets/atlas, dimensões reduzidas), animações, áudio (OGG Vorbis para música, WAV curto para SFX) e efeitos (partículas: preferir `CPUParticles2D` ou `GPUParticles2D` testadas no Compatibility; shaders simples). Ficar atento ao tamanho total do download.
9. **Testar a exportação Web com frequência** — não apenas no editor.
10. Ao encontrar uma limitação ou dependência específica da Web, **registrá-la na seção 12**.

## 3. Estado atual do projeto

Última atualização: 2026-11-13. Repositório: https://github.com/M4theusO/elements (privado, branch `master`).

**Concluído:**
- Fundação: `project.godot` (seção 9), estrutura de pastas (seção 7), Input Map e Collision Layers.
- **Marco 1, etapas 1–2 (movimentação e pulo da Terra):**
  - `core/resources/character_stats.gd` (`CharacterStats`) e `entities/characters/_shared/player_character.{tscn,gd}` (`PlayerCharacter`): aceleração/desaceleração (sensível ao analógico), gravidade com queda mais forte, pulo variável, coyote time, jump buffer, velocidade máxima de queda, troca automática de animação.
  - `entities/characters/terra/terra.tscn` (herdada) + `terra_stats.tres` + `terra_sprite_frames.tres`.
  - Colisão do corpo 16x46 em (0,-23); Hurtbox 14x44 em (0,-22). Altura mínima de passagem no level design: 3 tiles (48 px).
  - Animações da Terra: `idle` (arte original, 4 quadros), `walk`, `jump` e `fall` (**placeholders** gerados a partir do idle; ver seção 7, "Animações dos protagonistas").
  - `tests/movement_lab/movement_lab.tscn`: laboratório (chão, paredes, degraus de 1–4 tiles, plataforma one-way, câmera, 2 `TrainingDummy` em x 260 e 880), **cena principal temporária**.
- **Marco 1, etapa 3 (combate básico da Terra) — implementado, aguardando teste manual e commit:**
  - Componentes em `core/components/`: `HealthComponent`, `Hurtbox`, `Hitbox`, `MeleeAttack`; dados em `core/resources/attack_data.gd` (`AttackData`). Ver seção 9, "Combate".
  - Terra: `terra_basic_attack.tres` (dano 1; 0,08 / 0,10 / 0,22 s), Hitbox 20x16 em (18,-28), acionada por `attack`.
  - Inimigo de teste `entities/enemies/training_dummy/` (3 de vida, `Polygon2D` provisório, pisca e some ao morrer).
  - `tests/combat/combat_test.gd`: teste automatizado (64 verificações). Executar: `godot --headless --path . -s res://tests/combat/combat_test.gd`.
- `tests/animation/player_animation_test.gd`: teste automatizado versionado (69 verificações: parâmetros físicos aprovados, colliders, `SpriteFrames`, transições idle/walk/jump/fall, paredes, aterrissagem, flip, física medida, fallback). Executar na raiz do projeto: `godot --headless --path . -s res://tests/animation/player_animation_test.gd` (código de saída 0 = sucesso).

**Pendente / próximos passos possíveis:**
- Arte final de `walk`, `jump` e `fall` (substituir os PNGs mantendo nome e formato).
- Opcional: balanço da trança no `walk`.
- Teste visual no editor (F5) e na exportação Web; export templates 4.7.2 ainda **não instalados**, preset Web ainda não criado.
- Arte da animação `attack` da Terra (golpe com a manopla).
- Marco 1, próximas etapas: inimigos, habilidade sísmica, cenário destrutível, progressão.

**Não presuma que algo existe.** Antes de referenciar uma cena, script, asset, input action, layer de física ou autoload, verifique no repositório. Se não existir, informe e pergunte antes de criar.

> Atualize esta seção conforme marcos forem concluídos.

## 4. Estratégia de desenvolvimento

Desenvolvimento **incremental**, em pequenas etapas validáveis.

**Primeiro marco — protótipo jogável com Terra**, contemplando (cada item é uma etapa separada, implementada apenas quando solicitada):

1. Movimentação
2. Pulo
3. Combate básico
4. Inimigos
5. Habilidade sísmica
6. Cenário destrutível
7. Progressão

Os demais personagens (Aqua, Ignis, Aeris) **não** devem ser implementados até solicitação explícita — mas os sistemas do protótipo devem ser escritos de forma que possam ser reutilizados por eles sem duplicação.

## 5. Regras de trabalho

1. **Analise antes de alterar:** leia a estrutura existente e os arquivos relacionados antes de propor mudanças.
2. **Etapas pequenas:** implemente uma funcionalidade por vez; não agrupe várias etapas numa só entrega.
3. **Explique as alterações:** ao final de cada tarefa, liste arquivos criados/modificados e o porquê.
4. **Não modifique arquivos sem necessidade:** nada de refatorações, renomeações ou reformatações fora do escopo.
5. **Sem funcionalidades futuras:** não implemente nada que não tenha sido pedido, nem "ganchos" especulativos.
6. **Simplicidade primeiro:** prefira a solução mais simples que seja modular e escalável.
7. **Decisões arquiteturais:** avise e aguarde confirmação **antes** de aplicar decisões importantes (novos autoloads, mudanças de estrutura de pastas, sistema de estados, formato de dados, layers de colisão, sistema de save, etc.).
8. **Não presuma existência** de assets, cenas ou sistemas (ver seção 3).
9. **Valide antes de concluir:** revise scripts, aponte possíveis erros e o que precisa ser testado manualmente no editor (ver seção 10).
10. **Mantenha este arquivo atualizado** quando decisões forem tomadas ou convenções mudarem.

## 6. Princípios de arquitetura

- **Composição sobre herança profunda:** comportamentos reutilizáveis como componentes (nós filhos com script próprio), ex.: vida, hitbox/hurtbox, movimentação.
- **Dados separados de lógica:** atributos e configurações em `Resource` customizados (`.tres`), para que personagens, inimigos e habilidades sejam configuráveis sem duplicar código.
- **Sem duplicação entre personagens:** comportamento comum fica em scripts/componentes compartilhados; o que é específico de cada elemento fica isolado na pasta do personagem.
- **Baixo acoplamento:** comunicação preferencialmente via **signals**; evitar caminhos de nó frágeis (`get_node("../../X")`). Use `@export` para injetar referências.
- **Autoloads com parcimônia:** apenas para estado verdadeiramente global; cada novo autoload exige aprovação prévia.
- **Cenas autocontidas:** cada cena deve funcionar ao ser instanciada isoladamente (quando fizer sentido) e ser testável com F6.

> Estes princípios orientam as propostas. A forma concreta (ex.: máquina de estados por nós vs. enum, estrutura de componentes) será proposta e confirmada na etapa em que for necessária.

## 7. Estrutura de pastas (aprovada)

Organização **por funcionalidade**: cada personagem, inimigo, fase ou tela guarda na própria pasta sua cena, script, sprites e dados. O que é genérico e reutilizável fica em `core/`.

```
res://                           # raiz do projeto Godot e do repositório Git
├── core/                        # Código genérico, sem conteúdo específico do jogo
│   ├── autoload/                # Singletons globais (cada um aprovado antes de criar)
│   ├── components/              # Nós reutilizáveis (vida, hitbox/hurtbox, etc.)
│   ├── resources/               # Definições de Resource customizados (só scripts .gd)
│   └── utils/                   # Funções auxiliares puras
├── entities/                    # Tudo que tem comportamento no mundo
│   ├── characters/
│   │   ├── _shared/             # Base comum aos 4 protagonistas
│   │   ├── terra/               # Cena, script, sprites, dados (.tres), abilities/
│   │   ├── aqua/
│   │   ├── ignis/
│   │   └── aeris/
│   └── enemies/
│       └── _shared/             # Base comum a inimigos; cada inimigo ganha sua pasta
├── world/
│   ├── levels/                  # Fases/salas, uma subpasta por região do mapa
│   ├── tilesets/                # TileSets e suas texturas
│   └── props/                   # Objetos de cenário (destrutíveis, portas, plataformas)
├── ui/
│   ├── hud/                     # Elementos durante o jogo
│   ├── menus/                   # Menu principal, pausa, opções, tela "clique para começar"
│   └── theme/                   # Theme do Godot, estilos
├── assets/                      # Assets compartilhados, sem dono específico
│   ├── audio/music/
│   ├── audio/sfx/
│   ├── fonts/
│   └── shaders/                 # Compatíveis com o renderizador Compatibility
├── main/                        # Cena de entrada (boot) e fluxo entre telas
├── tests/                       # Cenas sandbox para testar sistemas isoladamente
└── builds/                      # Saída das exportações (ignorada no Git; .gdignore impede importação)
```

Regras:

- Scripts vinculados a uma cena ficam **ao lado da cena** (`entities/characters/terra/terra.tscn` + `terra.gd`).
- **Tipos** de dados (`character_data.gd`) ficam em `core/resources/`; **instâncias** (`terra_data.tres`) ficam na pasta da entidade.
- Habilidades específicas de um personagem ficam em `entities/characters/<nome>/abilities/`; só o sistema genérico de habilidades vai para `core/`.
- Assets usados por uma única entidade ficam na pasta dela (ex.: `entities/characters/terra/sprites/`); `assets/` é só para o que é compartilhado.
- Pastas vazias levam um `.gitkeep`, que pode ser removido quando a pasta receber conteúdo.
- Novas pastas de primeiro nível exigem aprovação.

### Animações dos protagonistas

- Cada protagonista define suas animações num `SpriteFrames` próprio (`entities/characters/<nome>/<nome>_sprite_frames.tres`), usado pelo `Visuals/AnimatedSprite2D` da cena herdada. A cena base não tem `SpriteFrames`.
- **Nomes padronizados** (constantes em `PlayerCharacter`): `idle`, `walk`, `jump`, `fall`, `attack`. Novos nomes só com aprovação.
- `attack` tem prioridade durante a preparação e a fase ativa do golpe; na recuperação volta à animação do estado físico. Se o `SpriteFrames` não tiver `attack`, a animação normal é mantida (sem cair para `idle`). Sem loop.
- `PlayerCharacter` escolhe a animação: no ar, `jump` subindo e `fall` descendo; no chão, `walk` com deslocamento horizontal real (`get_real_velocity()`, para que empurrar uma parede resulte em `idle`) e `idle` parado. Animação ausente no `SpriteFrames` cai para `idle`; sem `SpriteFrames`, nada acontece (sem erro).
- `jump` não tem loop (para no último quadro); `idle`, `walk` e `fall` têm loop.
- Spritesheets: quadros de 48x64, fundo transparente, personagem olhando para a direita. Animações no chão (`idle`, `walk`) com o pé apoiado na linha y = 60 do quadro; nas aéreas a linha é a mesma referência, mas os pés podem ficar acima dela.
- `terra_walk.png`, `terra_jump.png` e `terra_fall.png` atuais são **placeholders** gerados a partir do idle; a arte final substitui os arquivos mantendo nome e formato (8, 2 e 2 quadros).

## 8. Convenções de código (GDScript)

Seguir o [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html) oficial:

- **Arquivos e pastas:** `snake_case` (`health_component.gd`, `terra.tscn`).
- **Classes (`class_name`):** `PascalCase`. Use `class_name` apenas quando o tipo for referenciado em outros scripts.
- **Variáveis e funções:** `snake_case`; privadas com prefixo `_`.
- **Constantes e enums:** `CONSTANT_CASE`; enums com nome em `PascalCase`.
- **Signals:** `snake_case` no passado (`died`, `health_changed`).
- **Nós na árvore:** `PascalCase` (`HealthComponent`, `AnimatedSprite2D`).
- **Tipagem estática** sempre que possível (`var speed: float = 120.0`, `func take_damage(amount: int) -> void:`).
- **Ordem no script:** `class_name` / `extends` → signals → enums → constantes → `@export` → variáveis públicas → privadas → `@onready` → métodos built-in (`_ready`, `_physics_process`...) → métodos públicos → privados.
- Física e movimento em `_physics_process`; nada de números mágicos — use `@export` ou constantes.
- Comentários em português, objetivos, explicando o *porquê* quando não for óbvio.

## 9. Configuração do projeto

Já definido (em `project.godot`):

- Renderizador: **Compatibility** (`gl_compatibility`).
- Resolução interna (viewport): **640x360** — toda a arte e o level design são feitos nessa escala.
- Resolução de exibição inicial: **1280x720** (`window_width/height_override`), escala 2x.
- Stretch: mode `viewport`, aspect `keep`, scale mode `integer` — o jogo é renderizado em 640x360 e ampliado apenas por múltiplos inteiros; sobra de tela vira barras pretas. (`keep` é o valor padrão da Godot, por isso não aparece escrito no `project.godot`.)
- Filtro de textura padrão: **Nearest**.

Notas Web: no navegador, o tamanho do canvas é definido pela página/iframe (o override de janela não se aplica). No itch.io, configurar o embed em 1280x720 para escala 2x exata. A política de redimensionamento do canvas (`Canvas Resize Policy`) será definida ao criar o preset de exportação Web.

### Input Map (aprovado)

Dois esquemas de teclado ativos ao mesmo tempo + gamepad (layout Xbox / "standard" do navegador). Mouse não é usado no gameplay. Teclas em **physical keycode** (independe do layout do teclado). Todos os eventos com `device = -1` (qualquer dispositivo). Deadzone **0.25** em todas as ações.

| Ação | Esquema A | Esquema B | Gamepad |
|---|---|---|---|
| `move_left` | A | ← | Analógico esq. ← / D-pad ← |
| `move_right` | D | → | Analógico esq. → / D-pad → |
| `move_up` | W | ↑ | Analógico esq. ↑ / D-pad ↑ |
| `move_down` | S | ↓ | Analógico esq. ↓ / D-pad ↓ |
| `jump` | K, Espaço | Z | A (inferior) |
| `attack` | J | X | X (esquerdo) |
| `ability` | L | C | Y (superior) |
| `interact` | E | ↑ (compartilhado com `move_up`) | B (direito) |
| `pause` | Esc, P | Esc, P | Start |

- `pause` também em P porque, em tela cheia no navegador, Esc sai da tela cheia e não chega ao jogo.
- Ações `ui_*` mantidas no padrão da Godot por enquanto.
- Reservado para o futuro (não criado): `dash`, troca de personagem, mapa, inventário — Q, R, M e LB/RB/LT/RT livres. **Não usar Tab, Ctrl/Alt+tecla ou F1–F12.**
- Novas ações exigem aprovação e devem ser adicionadas a esta tabela.

### Collision Layers 2D (aprovado)

Conceito na Godot: **layer = "o que eu sou"**; **mask = "o que eu procuro"**. A detecta B se a *mask de A* contém a *layer de B* (detecção unidirecional). `StaticBody2D`/`TileMapLayer` não precisam de mask. `Area2D` que procura precisa de `monitoring`; a que é encontrada precisa de `monitorable`.

| # | Nome | Responsabilidade | Nó típico |
|---|---|---|---|
| 1 | `world` | Chão, paredes, teto | `TileMapLayer` (physics layer do TileSet) |
| 2 | `platforms` | Plataformas atravessáveis (one-way); separada de `world` para o jogador poder desligá-la da mask ao descer (`move_down`) | `TileMapLayer` / `StaticBody2D` |
| 3 | `player` | Corpo físico do protagonista ativo | `CharacterBody2D` |
| 4 | `enemies` | Corpo físico dos inimigos | `CharacterBody2D` |
| 5 | `player_hurtbox` | Área onde o jogador recebe dano | `Area2D` (Hurtbox) |
| 6 | `enemy_hurtbox` | Área onde inimigos recebem dano | `Area2D` (Hurtbox) |
| 7 | `destructibles` | Paredes/objetos quebráveis e sólidos | `StaticBody2D` |
| 8 | `interactables` | NPCs, alavancas, baús, portas | `Area2D` |

Layers 9–32 livres. **Nenhuma layer nova sem aprovação.**

#### Separação de responsabilidades

- **Corpo físico** (`CharacterBody2D`): só movimento e colisão com o cenário. Não recebe nem causa dano.
- **Hitbox** (`Area2D`, *causa* dano): **não ocupa layer**; apenas procura (mask) hurtboxes/destrutíveis. É o lado que detecta o acerto. Golpes, habilidades e projéteis são todos hitboxes — projéteis apenas adicionam `world` à mask para sumir ao bater em paredes.
- **Hurtbox** (`Area2D`, *recebe* dano): ocupa `player_hurtbox` ou `enemy_hurtbox`, sem mask. Formato independente do corpo físico; invencibilidade = desligar `monitorable`.
- **Sensor de interação** (`Area2D` do jogador): sem layer, mask `interactables`.
- **Zonas de gatilho** (troca de sala, checkpoint, câmera): sem layer, mask `player`.

Os lados (jogador × inimigo) são definidos pelas layers; o **tipo** de ataque (golpe, projétil, habilidade) não.

#### Matriz de detecção

Linhas = quem procura (mask); colunas = layer do alvo.

| Quem procura ↓ / Alvo → | world | platforms | player | enemies | player_hurtbox | enemy_hurtbox | destructibles | interactables |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| Corpo do jogador | ✅ | ✅ | | | | | ✅ | |
| Corpo do inimigo | ✅ | ✅ | | | | | ✅ | |
| Hitbox do jogador | | | | | | ✅ | ✅ | |
| Projétil do jogador | ✅ | | | | | ✅ | ✅ | |
| Hitbox do inimigo (golpe, contato) | | | | | ✅ | | | |
| Projétil do inimigo | ✅ | | | | ✅ | | | |
| Hitbox ambiental (espinhos, lava) | | | | | ✅ | | | |
| Sensor de interação | | | | | | | | ✅ |
| Zonas de gatilho | | | ✅ | | | | | |

#### Regras de design

- **Jogador e inimigos não têm colisão física entre si** (atravessam-se; o contato causa dano via hitbox do inimigo). Inimigos também não colidem entre si.
- **Os quatro protagonistas compartilham a mesma arquitetura de colisões.** Diferenças elementais ficam nos **dados da hitbox** (dano, elemento, flags como "quebra rocha"), nunca em layers. Ex.: parede que só a habilidade sísmica quebra está em `destructibles` e o componente dela rejeita golpes de outro tipo.
- **Armadilhas e perigos ambientais são hitboxes ambientais** — conceito próprio, distinto de ataques de inimigos, mas sem layer própria (mask `player_hurtbox`).
- **Destrutíveis no protótipo são cenas próprias com `StaticBody2D`**, não tiles do `TileMapLayer`.
- Configurar layers/masks preferencialmente no Inspector das cenas. Constantes de código para layers só serão criadas no primeiro uso real em script, com aprovação.

### Combate

- **`HealthComponent`** (`Node`): `max_health`/`current_health` inteiros, `take_damage(amount)`; signals `damaged(amount)` e `died` (uma única vez). Vida nunca negativa; dano zero/negativo ou após a morte é ignorado.
- **`Hurtbox`** (`Area2D`): `receive_hit(damage)` emite `hit_received` e repassa ao `HealthComponent` exportado (`health`).
- **`Hitbox`** (`Area2D`): sem layer; mask do alvo (jogador: `enemy_hurtbox`; `destructibles` entra na etapa de cenário destrutível). `activate()`/`deactivate()` alteram `monitoring` com `set_deferred`. Enquanto ativa, consulta as sobreposições a cada tick; cada `Hurtbox` é atingida no máximo uma vez por ativação (vários alvos por golpe são permitidos). `show_debug` desenha o alcance (provisório: translúcido na preparação, forte na fase ativa).
- **`MeleeAttack`** (`Node`): fases `READY → WINDUP → ACTIVE → RECOVERY` contadas em `_physics_process` a partir de um `AttackData`; `try_attack()`, `is_striking()` (preparação ou ativa), `is_busy()`; signals `attack_started`/`attack_finished`. Roda com `process_physics_priority = -1` para o personagem ler o estado do tick atual.
- **`PlayerCharacter`**: a ação `attack` chama `try_attack()`; o lado fica travado enquanto `is_striking()`; movimento e física não mudam durante o golpe. A `Hitbox` fica em `Visuals`, então acompanha o flip.
- Cada personagem configura na própria cena o `AttackData` (`MeleeAttack.attack`) e o formato/posição de `Visuals/Hitbox/CollisionShape2D`.

### A definir

Itens a serem decididos e registrados aqui quando forem criados — **não criar sem aprovação**:
- Autoloads.

## 10. Validação antes de concluir uma tarefa

- Revisar os scripts alterados: tipagem, referências `@onready`/`@export` válidas, signals conectados, nomes de nós coerentes com a cena.
- Confirmar que as APIs usadas existem e se comportam como esperado na **Godot 4.7.2** (não assumir APIs de versões anteriores ou futuras).
- Conferir se input actions, layers e recursos referenciados existem.
- **Checar compatibilidade Web** contra a seção 2.1 (threads, sistema de arquivos, operações bloqueantes, entrada, áudio).
- Quando o executável do Godot estiver disponível no PATH, checar erros de parse com:
  `godot --headless --check-only --script <caminho/script.gd>`
  (caso não esteja disponível, informar que a validação foi apenas por revisão).
- Listar explicitamente o que o usuário precisa testar **no editor** e **na exportação Web** (navegador), e quais riscos/pontos de atenção existem.
- Registrar na seção 12 qualquer limitação ou dependência encontrada.
- Nunca declarar uma tarefa concluída se houver erro conhecido não reportado.

## 11. Arquivos que não devem ser editados manualmente

- `.godot/` (cache do editor — não versionar).
- Arquivos `.import` e `.uid` gerados pelo Godot.
- Evitar editar `.tscn`/`.tres` à mão quando a alteração for complexa; preferir instruir o usuário a fazer no editor ou editar com cuidado, preservando IDs e `ext_resource`.
- Builds de exportação (pasta de saída da exportação Web/Windows) — não versionar.

## 12. Limitações e dependências registradas

Registro de limitações (especialmente da Web) e dependências encontradas durante o desenvolvimento. Formato: data — descrição — impacto/solução adotada.

- _(nenhuma registrada ainda)_
