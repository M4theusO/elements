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

Última atualização: 2026-11-14. Repositório: https://github.com/M4theusO/elements (privado, branch `master`).

**Concluído:**
- Fundação: `project.godot` (seção 9), estrutura de pastas (seção 7), Input Map e Collision Layers.
- **Marco 1, etapas 1–2 (movimentação e pulo da Terra):**
  - `core/resources/character_stats.gd` (`CharacterStats`) e `entities/characters/_shared/player_character.{tscn,gd}` (`PlayerCharacter`): aceleração/desaceleração (sensível ao analógico), gravidade com queda mais forte, pulo variável, coyote time, jump buffer, velocidade máxima de queda, troca automática de animação.
  - `entities/characters/terra/terra.tscn` (herdada) + `terra_stats.tres` + `terra_sprite_frames.tres`.
  - Colisão do corpo 16x46 em (0,-23); Hurtbox 14x44 em (0,-22). Altura mínima de passagem no level design: 3 tiles (48 px).
  - Animações da Terra: `idle` (arte original, 4 quadros), `walk` (5 quadros), `jump` e `fall` (2 quadros cada), `attack` e `ability` (4 quadros 64x64 cada), `death` (6 quadros 64x64), estas com arte gerada por IA e convertida; ver seção 7, "Animações dos protagonistas".
  - `tests/movement_lab/movement_lab.tscn`: laboratório (chão, paredes, degraus de 1–4 tiles, plataforma one-way, câmera, 2 `TrainingDummy` em x 260 e 880), **cena principal temporária**.
- **Marco 1, etapa 3 (combate básico da Terra) — validado manualmente e commitado (`16f4532`):**
  - Componentes em `core/components/`: `HealthComponent`, `Hurtbox`, `Hitbox`, `MeleeAttack`; dados em `core/resources/attack_data.gd` (`AttackData`). Ver seção 9, "Combate".
  - Terra: `terra_basic_attack.tres` (dano 1; 0,08 / 0,10 / 0,22 s), Hitbox 20x16 em (18,-28), acionada por `attack`.
  - Inimigo de teste `entities/enemies/training_dummy/` (3 de vida, `Polygon2D` provisório, pisca e some ao morrer).
  - `tests/combat/combat_test.gd`: teste automatizado (66 verificações, incluindo o formato e a sincronia da animação `attack`). Executar: `godot --headless --path . -s res://tests/combat/combat_test.gd`.
- **Marco 1, etapa 5 (Punho Sísmico da Terra) — validado manualmente e commitado:**
  - `core/components/character_ability.gd` (`CharacterAbility`): interface mínima da habilidade (ação `ability`).
  - `entities/characters/terra/abilities/seismic_fist.gd` (`SeismicFist`) + `seismic_wave.{tscn,gd}` (`SeismicWave`, subclasse de `Hitbox`). Ver seção 9, "Combate".
  - Efeito da onda: `sprites/terra_seismic_wave.png` + `abilities/seismic_wave_sprite_frames.tres` (animação `wave`); retângulos de depuração desligados na onda e no soco da Terra (ver seções 7 e 9).
  - `tests/combat/seismic_fist_test.gd`: teste automatizado (83 verificações, incluindo o formato e a sincronia das animações `ability` e `wave`). Executar: `godot --headless --path . -s res://tests/combat/seismic_fist_test.gd`.
- **Marco 1, etapa 4 (primeiro inimigo: Fragmento Vivo) — implementado, aguardando validação manual (não commitado):**
  - Base `entities/enemies/_shared/enemy.gd` (`Enemy`); `TrainingDummy` migrado para ela (mesmo comportamento).
  - `entities/enemies/living_fragment/` (`LivingFragment`): patrulha, detecção com linha de visão, perseguição, investida, recarga; sprites idle/walk/attack/hit/death (arte original reduzida, quadros 64x48) ligados aos estados. Ver seção 9, "Inimigos".
  - Vida da Terra: `HealthComponent` (5) na cena base do jogador; `Hurtbox` com invulnerabilidade de 0,6 s; feedback visual provisório (clarão + piscar). Morte: perde o controle e toca `death` (fica caída); sem respawn ou HUD.
  - MovementLab: `LivingFragmentFloor` (x 1240, perto da parede direita) e `LivingFragmentPlatform` (sobre a plataforma one-way). `CrystalBurrower` no chão em x 1040 (território 976–1104, sob a plataforma one-way).
  - `tests/enemies/living_fragment_test.gd`: teste automatizado (103 verificações, incluindo a morte da Terra). Executar: `godot --headless --path . -s res://tests/enemies/living_fragment_test.gd`.
- `tests/animation/player_animation_test.gd`: teste automatizado versionado (69 verificações: parâmetros físicos aprovados, colliders, `SpriteFrames`, transições idle/walk/jump/fall, paredes, aterrissagem, flip, física medida, fallback). Executar na raiz do projeto: `godot --headless --path . -s res://tests/animation/player_animation_test.gd` (código de saída 0 = sucesso).
- `tests/combat/shared_combat_test.gd`: teste automatizado (44 verificações) da base compartilhada: direção do golpe (`Hitbox` → `Hurtbox`, soco e onda sísmica reais), gancho `_get_damage_taken`, `MeleeAttack.finish_active()` e helpers de `Enemy`. Executar: `godot --headless --path . -s res://tests/combat/shared_combat_test.gd`.
- `tests/enemies/crystal_burrower_test.gd`: teste automatizado do Escavador de Cristal (200 verificações: configuração, pausa, patrulha, território, paredes, bordas, gravidade, detecção frontal/lado/altura/linha de visão, dano, morte; ataque: CHARGE/DASH/STUNNED, tempos, distância, parede, borda, pulo sobre a investida, acerto único, recarga, morte em cada fase; carapaça: frente/costas, acumulador fracionário, direção desconhecida, orientação, invulnerabilidade, feedback, reação, golpes em cada fase, soco e onda reais, morte; sprites: 7 folhas, SpriteFrames, sincronia com o combate, troca de animações por estado, hit, interrupção, orientação, clarões, death e remoção). Executar: `godot --headless --path . -s res://tests/enemies/crystal_burrower_test.gd`.
- **Segundo inimigo: Escavador de Cristal — concluído, validado manualmente e commitado** (planejamento aprovado em 2026-11-14). Etapas: 1, base compartilhada (helpers em `Enemy`, direção do golpe, gancho de dano, `finish_active()`, `73f0b2d`); 2, cena base, IDLE/PATROL e detecção frontal (`fcd22a0`); 3, CHARGE → DASH → STUNNED e recarga (`69c8aa2`); 4, carapaça, dano direcional e reação a golpes (`fa7452e`); 5A, sprite idle (`fc2ab61`); 5B, as 7 animações integradas à máquina de estados. Ver seção 9, "Inimigos".
- **Cenário: Reino das Profundezas (região da Terra), primeiro conjunto de terreno — atlas, TileSet e sala de teste validados manualmente e commitados.** Ver seção 9, "Cenário".
  - `world/tilesets/depths/`: `depths_terrain.png` (atlas 8x4 de 16x16), `depths_palette.png` (17 cores) e `depths_tileset.tres`.
  - `world/levels/depths/depths_test_room.tscn`: sala de teste jogável (rodar com F6; a cena principal continua sendo o MovementLab).
  - Testes: `tests/tilesets/depths_terrain_test.gd` (190 verificações: dimensões, paleta, transparência, grade, bordas, apoio, contorno, emendas, cantos internos, variações), `tests/tilesets/depths_tileset_test.gd` (21: atlas, camadas de física, colisões, terrain sets e pintura real com o pincel de terreno) e `tests/levels/depths_test_room_test.gd` (37: estrutura, peças, chão sem tropeço nas emendas, paredes, degraus, teto, one-way, onda sísmica e Fragmento Vivo sobre tiles).
  - Fontes e scripts de geração (atlas, TileSet, sala, prévias) fora do projeto, em `Desktop\sprites\fase_terra\atlas_build\` (README com instruções; o processo é determinístico).
- **Reino das Profundezas: fundo com parallax (3 camadas) — validado manualmente e commitado.** Ver seção 9, "Cenário".
  - `world/levels/depths/backgrounds/`: `depths_parallax.tscn` (3 `Parallax2D`), `depths_bg_far/mid/near.png` e `depths_bg_palette.png` (12 cores). Instância `Background` na sala de teste, antes do `Terrain`.
  - `tests/levels/depths_parallax_test.gd` (97 verificações: imagens, paleta, alfa, pixel inteiro, zonas, emendas, importação, cena sem colisões/scripts, ligação com a sala, cobertura real da tela na sala e em salas maiores, configurações gráficas). Executar: `godot --headless --path . -s res://tests/levels/depths_parallax_test.gd`.
  - Fontes (imagens de IA), conversão, prévias e instalação fora do projeto, em `Desktop\sprites\fase_terra\parallax_build\` (README; processo determinístico).
- **Reino das Profundezas: props decorativos, grupo 1 (cristais) — validado manualmente e commitado.** Ver seção 9, "Cenário".
  - `world/props/depths/`: `depths_props_palette.png` (24 cores) e `crystals/` (4 PNGs + 4 cenas `Sprite2D`). Nó `Props` na sala de teste com 8 cristais.
  - `tests/props/depths_crystals_test.gd` (91 verificações: paleta, imagens, âncoras, importação, cenas sem script/colisão, uso na sala, apoio real no terreno, regras de posicionamento, preservação). Executar: `godot --headless --path . -s res://tests/props/depths_crystals_test.gd`.
  - Ordem de desenho confirmada com capturas reais (onda sísmica `top_level`, Terra e Fragmento Vivo por cima dos cristais). Fontes, conversão, prévias, instalação e capturas fora do projeto, em `Desktop\sprites\fase_terra\props_build\` (README).
- **Reino das Profundezas: props decorativos, grupo 2 (vegetação) — validado manualmente e commitado.** Ver seção 9, "Cenário".
  - `world/props/depths/vegetation/`: 6 PNGs + 6 cenas `Sprite2D`. 8 instâncias no `Props` da sala, depois dos cristais.
  - `tests/props/depths_vegetation_test.gd` (114 verificações: cores por sprite, imagens, âncoras, importação, cenas sem script/colisão, apoio no desenho real do terreno, superfícies jogáveis livres, altura livre sob peças penduradas, regras do caminho principal, preservação). Executar: `godot --headless --path . -s res://tests/props/depths_vegetation_test.gd`. O teste dos cristais passou a aceitar outras famílias no `Props` (só cenas de `world/props/depths/`).
  - Sala: o `LivingFragmentPlatform` foi movido no editor (2026-11-14, aprovado) da plataforma larga para o chão em (302, 316), ao pé do 1º degrau; testes da sala, do parallax e dos props atualizados. A cobertura de inimigo sobre plataforma one-way no teste da sala vem de um Fragmento extra criado só no teste.
  - Observação visual (sem ação decidida): na patrulha (x 254–343), esse Fragmento passa na frente do `CrystalSmallFloor` e do `FungiTallCorner` e, ao virar na face do 1º degrau, o desenho dele avança ~6 px sobre o degrau (o corpo de 18 px encosta na parede). Opções, se desejado: mover o `FungiTallCorner` ou levar o Fragmento para x ≤ 289.
- **Galerias Esquecidas (Reino das Profundezas), etapa 1: infraestrutura de salas — commitada (`9469fef`), feita em outra sessão; ainda não documentada em detalhe aqui.**
  - `main/game.tscn` + `game.gd` (`Game`): cena persistente que carrega a sala atual em `RoomSlot`, põe a Terra (instância única, nunca recriada nem trocada de pai) numa entrada e aplica os limites da câmera; tem um `Fade` (`CanvasLayer`). Por enquanto carrega só a sala inicial (`start_room`, entrada `start`); transições entre salas ainda não existem. **Não é a cena principal** (continua o MovementLab).
  - `world/levels/_shared/room.gd` (`Room`): base das salas (sem a Terra). Estrutura esperada: `Background`, `Terrain`, `Props`, `Enemies`, `Entrances` (`Marker2D` por entrada; o nome é o identificador, marca os pés da Terra), `Exits`; `camera_bounds` (múltiplos de 16, mínimo 640x368).
  - `world/levels/depths/forgotten_galleries/room_01_awakening.tscn`: Sala 01 — Despertar (fundo com parallax, terreno, 6 cristais, entrada `start`; sem inimigos).
  - `tests/levels/forgotten_galleries/room_infra_test.gd` (82 verificações: estrutura, carregamento, Terra única na entrada, câmera, fundo, terreno, percurso real com a física da Terra). Executar: `godot --headless --path . -s res://tests/levels/forgotten_galleries/room_infra_test.gd`.

**Pendente / próximos passos possíveis:**
- Opcional: refazer `jump`/`fall` na escala exata do `idle` (hoje ~10–15% maiores).
- Opcional: balanço da trança no `walk`.
- Teste visual no editor (F5) e na exportação Web; export templates 4.7.2 ainda **não instalados**, preset Web ainda não criado.
- Opcional, após teste no jogo: mostrar a volta à guarda na recuperação do golpe e o "depois do impacto" após a liberação do Punho Sísmico (hoje ambos voltam direto ao idle; exige mudar a regra do `attack`/`ability`).
- Respawn da Terra (hoje fica caída após a morte; é preciso reiniciar a cena) e HUD de vida.
- Marco 1, próximas etapas: cenário destrutível (incluir `destructibles` na mask da onda sísmica), progressão.
- Galerias Esquecidas: próximas etapas da outra sessão (transições entre salas, novas salas); documentar aqui as decisões dessa frente (cena `Game`, base `Room`) quando forem retomadas.
- Reino das Profundezas: props, grupos 3–4 (rochas, ruínas; catálogo e paleta aprovados, ver seção 9, "Cenário"; mesmo processo dos cristais e da vegetação: guia + folha da IA em `props_build`, `convert_props.gd`, aprovação visual, `build_props.gd`, teste e capturas reais), primeira fase definitiva; descer de plataformas one-way (`move_down`, ainda não implementado); rampas.

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
│   ├── levels/                  # Fases/salas, uma subpasta por região do mapa (depths/ = Reino das Profundezas)
│   ├── tilesets/                # TileSets e suas texturas, uma subpasta por região (depths/)
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
- **Nomes padronizados** (constantes em `PlayerCharacter`): `idle`, `walk`, `jump`, `fall`, `attack`, `ability`, `death`. Novos nomes só com aprovação.
- `attack` tem prioridade durante a preparação e a fase ativa do golpe; na recuperação volta à animação do estado físico. Se o `SpriteFrames` não tiver `attack`, a animação normal é mantida (sem cair para `idle`). Sem loop.
- `ability` segue a mesma regra, durante a preparação da habilidade especial.
- `death` toca uma vez ao morrer (sem loop, fica no último quadro) e tem prioridade sobre todas as outras; ausente no `SpriteFrames`, cai para `idle`.
- `PlayerCharacter` escolhe a animação: no ar, `jump` subindo e `fall` descendo; no chão, `walk` com deslocamento horizontal real (`get_real_velocity()`, para que empurrar uma parede resulte em `idle`) e `idle` parado. Animação ausente no `SpriteFrames` cai para `idle`; sem `SpriteFrames`, nada acontece (sem erro).
- `jump` não tem loop (para no último quadro); `idle`, `walk` e `fall` têm loop.
- Spritesheets: quadros de 48x64 (exceção: `attack`, `ability` e `death` em 64x64, ver abaixo), fundo transparente, personagem olhando para a direita. Animações no chão (`idle`, `walk`) com o pé apoiado na linha y = 60 do quadro; nas aéreas a linha é a mesma referência, mas os pés podem ficar acima dela.
- `terra_jump.png` (impulso, subida) e `terra_fall.png` (ápice, descida) vêm de uma folha de 6 poses gerada por IA e convertida para a grade 48x64 (amostragem do centro de cada bloco, fundo magenta removido, poses centralizadas no corpo; pés no máximo em y = 60). A folha completa, com agachar e aterrissar, está fora do projeto (`Desktop\sprites\personagens\terra\terra_jump_6poses_48x64.png`). A Terra nelas fica cerca de 10–15% maior que no `idle`.
- `terra_walk.png`: 5 quadros a 7,5 FPS (ciclo de 0,67 s), mesma origem e conversão do pulo, mesma altura do `idle` (51 px); pés em y = 60 em todos os quadros e centralização pelo tronco (metade de cima), para as pernas balançarem sem a personagem tremer. A folha gerada tinha 6 quadros; o último (quase parado, igual ao primeiro) foi removido porque travava o loop. A folha de 6 quadros e a imagem original da IA estão fora do projeto (`Desktop\sprites\personagens\terra\`).
- `terra_attack.png`: 4 quadros de **64x64** (recuo, carga, soco, soco estendido). O corpo fica na mesma posição dos quadros 48x64 (origem em x = 25, mesmo `offset` do `AnimatedSprite2D`) e os 16 px extras ficam à frente, para a manopla; funciona com o flip porque ele é feito em `Visuals.scale.x`. Pés em y = 60; nas poses de soco o corpo avança 1–3 px para a trança e o pé de trás não saírem do quadro. Sincronia com o golpe: 60 FPS, durações 2,5 / 2,5 / 3 / 3 = 5 ticks na preparação (quadros 0–1) e 6 na fase ativa (quadros 2–3, punho dentro da hitbox). A guarda inicial e a volta à guarda ficaram de fora (folha de 6 poses em `Desktop\sprites\personagens\terra\terra_attack_6poses_64x64.png`). Na guarda a Terra tem ~44 px de altura (postura baixa e arte um pouco menor que o `idle`).
- `terra_seismic_fist.png` (animação `ability`): 4 quadros de **64x64** (agachar, erguer o punho, descer, impacto com a terra explodindo), mesma regra de posição do `attack`. Sincronia com a preparação de 0,25 s: 60 FPS, durações 4 / 4 / 4 / 3 = 15 ticks; o impacto ocupa os últimos 3 ticks, logo antes de a onda nascer. A arte original tinha pixels finos e irregulares (sem grade detectável); foi reduzida por moda (cor mais frequente de cada área), com a guarda ajustada para os 51 px do `idle`. Guarda, base e "depois do impacto" ficaram de fora (folha de 7 poses em `Desktop\sprites\personagens\terra\terra_seismic_fist_7poses_64x64.png`).
- `terra_death.png` (animação `death`): 6 quadros de **64x64** (golpe recebido, recuo, cambaleio, ajoelhada, de quatro, caída), 8 FPS, sem loop (0,75 s). Mesma conversão do Punho Sísmico (redução por moda, escala 6,41 = 327 px da pose em pé → 51 px do `idle`; borda magenta removida), pés em y = 60. Quadros 0–3 alinhados pelo tronco ao `idle` (centro em x = 20); nos dois deitados a borda de trás fica na mesma posição do quadro ajoelhado (x = 4) e o corpo cai para a frente (até x = 58). Todas as 6 poses foram usadas; a imagem original da IA está em `Desktop\sprites\personagens\terra\terra_death.png` (2172x724, fundo magenta).
- `terra_seismic_wave.png` (efeito da `SeismicWave`, animação `wave` em `abilities/seismic_wave_sprite_frames.tres`): 6 quadros de **80x40** (a terra sobe, pico de pedras, assenta), 15 FPS, sem loop = 0,4 s, o mesmo tempo do percurso de 96 px. Olha para a direita (espelhado com `flip_h` quando a onda vai para a esquerda); base das pedras na última linha do quadro e centro em x = 40 (`centered` desligado, `offset` (-40,-40)), maior quadro 69x34. Redução por moda, fator 5 (tamanho do pixel da arte original), quadros alinhados pela base comum e centralizados pela largura. Original em `Desktop\sprites\personagens\terra\terra_seismic-effect.png` (2172x724, fundo magenta).
- Arte nova: não redimensionar pixel art por fator não inteiro (estraga os pixels). Imagens de gerador devem vir com fundo magenta sólido; a conversão é feita por script (amostragem do centro dos blocos quando a grade é regular; redução por moda quando não é).

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
- **Hurtbox** (`Area2D`, *recebe* dano): ocupa `player_hurtbox` ou `enemy_hurtbox`, sem mask. Formato independente do corpo físico. Invencibilidade temporária (após dano) = `invulnerability_time` da `Hurtbox`, que ignora golpes logicamente (vale também para dois golpes no mesmo tick); desligar `monitorable` fica para remover a hurtbox de vez (ex.: morte do inimigo).
- **Sensor de interação** (`Area2D` do jogador): sem layer, mask `interactables`.
- **Zonas de gatilho** (troca de sala, checkpoint, câmera): sem layer, mask `player`.
- **Zona de detecção do inimigo** (`Area2D`): sem layer, mask `player`, `monitorable` desligado.

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
| Zona de detecção do inimigo | | | ✅ | | | | | |

#### Regras de design

- **Jogador e inimigos não têm colisão física entre si** (atravessam-se; o contato causa dano via hitbox do inimigo). Inimigos também não colidem entre si.
- **Os quatro protagonistas compartilham a mesma arquitetura de colisões.** Diferenças elementais ficam nos **dados da hitbox** (dano, elemento, flags como "quebra rocha"), nunca em layers. Ex.: parede que só a habilidade sísmica quebra está em `destructibles` e o componente dela rejeita golpes de outro tipo.
- **Armadilhas e perigos ambientais são hitboxes ambientais** — conceito próprio, distinto de ataques de inimigos, mas sem layer própria (mask `player_hurtbox`).
- **Destrutíveis no protótipo são cenas próprias com `StaticBody2D`**, não tiles do `TileMapLayer`.
- Configurar layers/masks preferencialmente no Inspector das cenas. Constantes de código para layers só serão criadas no primeiro uso real em script, com aprovação.

### Combate

- **`HealthComponent`** (`Node`): `max_health`/`current_health` inteiros, `take_damage(amount)`; signals `damaged(amount)` e `died` (uma única vez). Vida nunca negativa; dano zero/negativo ou após a morte é ignorado.
- **`Hurtbox`** (`Area2D`): `receive_hit(damage, hit_direction := Vector2.ZERO)` passa o dano pelo gancho `_get_damage_taken(damage, hit_direction) -> int` (padrão: sem alteração; negativo vira 0), emite `hit_received` com o dano resultante (pode ser 0) e repassa ao `HealthComponent` exportado (`health`). `get_last_hit_direction()`: direção do último golpe aceito (`Vector2.ZERO` = desconhecida, ex.: chamadas diretas). `invulnerability_time` (padrão 0 = desligado): após um golpe aceito, ignora novos golpes por esse tempo (`is_invulnerable()`, `get_invulnerability_left()`); roda com `process_physics_priority = -1` para a duração ser exata (0,6 s = 36 ticks).
- **Vida da Terra** (cena base do jogador): `HealthComponent` 5 de vida; `Hurtbox` com invulnerabilidade 0,6 s. `PlayerCharacter` só faz o feedback visual (clarão em `Visuals.modulate` + sprite piscando em `self_modulate`), sem alterar movimento, pulo, golpe ou habilidade. Em 0 de vida, novos golpes são ignorados e a Terra morre: sem controle (só gravidade e desaceleração natural até parar), golpe interrompido (`MeleeAttack` desligado, hitbox desativada), habilidade cancelada (`CharacterAbility.cancel()`), sem piscar, animação `death`. Sem respawn ainda.
- **`Hitbox`** (`Area2D`): sem layer; mask do alvo (jogador: `enemy_hurtbox`; `destructibles` entra na etapa de cenário destrutível). `activate()`/`deactivate()` alteram `monitoring` com `set_deferred`. Enquanto ativa, consulta as sobreposições a cada tick; cada `Hurtbox` é atingida no máximo uma vez por ativação (vários alvos por golpe são permitidos). `show_debug` desenha o alcance (translúcido na preparação, forte na fase ativa); ligado por padrão para testar hitboxes novas e desligado nas cenas que já têm arte (soco da Terra, onda sísmica, investida do Fragmento Vivo). `get_hit_direction() -> Vector2`: trajetória do golpe no mundo, repassada à `Hurtbox`; padrão = eixo x global da hitbox (acompanha flip e rotação de `Visuals`); hitboxes que se movem sozinhas sobrescrevem com a direção do movimento (`SeismicWave`: `(±1, 0)`; projéteis futuros: a velocidade normalizada).
- **`MeleeAttack`** (`Node`): fases `READY → WINDUP → ACTIVE → RECOVERY` contadas em `_physics_process` a partir de um `AttackData`; `try_attack()`, `is_striking()` (preparação ou ativa), `is_busy()`, `finish_active()` (encerra a fase ativa antes do tempo: desliga a hitbox e começa a recuperação completa a partir daquele tick; fora da fase ativa não faz nada e retorna false); signals `attack_started`/`attack_finished`. Roda com `process_physics_priority = -1` para o personagem ler o estado do tick atual.
- **`PlayerCharacter`**: a ação `attack` chama `try_attack()`; o lado fica travado enquanto `is_striking()`; movimento e física não mudam durante o golpe. A `Hitbox` fica em `Visuals`, então acompanha o flip.
- Cada personagem configura na própria cena o `AttackData` (`MeleeAttack.attack`) e o formato/posição de `Visuals/Hitbox/CollisionShape2D`.

#### Habilidades especiais

- **`CharacterAbility`** (`Node`, `core/components/`): interface mínima — `try_activate() -> bool` e `is_casting() -> bool` (preparação). Não há sistema genérico de habilidades; ele só será criado quando houver uma segunda habilidade real.
- **`PlayerCharacter`**: `@export var ability: CharacterAbility` (vazio na cena base). A ação `ability` chama `try_activate()`, exceto durante o golpe básico (`is_striking()`); o golpe básico é ignorado enquanto `is_casting()`; a direção fica travada durante a preparação. `get_facing()` expõe o lado (1/-1).
- Habilidades concretas ficam em `entities/characters/<nome>/abilities/`, como nó filho na cena do personagem, e rodam com `process_physics_priority = -1`.
- **Punho Sísmico da Terra** (`SeismicFist`, valores em `@export` no nó da `terra.tscn`): só no chão; preparação 0,25 s (direção travada, movimento livre; a onda pendente fica invisível, o aviso é a própria animação `ability`); sair do chão na preparação cancela sem onda, dano ou recarga. A `SeismicWave` (`Hitbox` com `top_level`, filha da Terra, mask `enemy_hurtbox`, área 32x16 em (0,-8)) nasce 12 px à frente e percorre 96 px a 240 px/s, dano 2 (uma vez por alvo); alcance da borda frontal: 124 px do centro da Terra. Na liberação toca a animação `wave` (0,4 s, espelhada para a esquerda). Ao parar, o dano acaba na hora e a onda fica parada até a animação terminar; se for bloqueada já no primeiro passo (nasceria dentro de uma parede), some na hora. A cada tick verifica a posição futura com raycasts: parede (`wall_mask` = world) e chão sob o novo centro (`ground_mask` = world + platforms; plataformas one-way contam como chão e não como parede); some em paredes, bordas ou ao fim do alcance. Recarga 1,5 s a partir da liberação.

#### Inimigos

- **`Enemy`** (`entities/enemies/_shared/enemy.gd`, `CharacterBody2D`): base mínima — liga `HealthComponent`/`Hurtbox`, pisca ao receber dano, ao morrer desliga o `monitorable` da hurtbox, chama o gancho `_on_death()` e some após o piscar, a menos que `_play_death_animation()` retorne true (o inimigo cuida de sumir; padrão false). Sem IA nem estados. Helpers genéricos usados pelos inimigos (nenhum roda sozinho): `get_facing()`/`_set_facing()` (escala de `Visuals`), `_apply_gravity(delta, max_fall_speed)`, `_has_ground_ahead(direction, step, ground_mask)` (largura lida do `CollisionShape2D` retangular), `_has_line_of_sight(target, eye_height, target_height, sight_mask)`, `_has_animation()` e `_play(anim, restart, speed_scale)` (sobre `Visuals/AnimatedSprite2D`, opcional). Cena precisa de `Visuals` (`Node2D`), `HealthComponent`, `Hurtbox`. Inimigos não usam invulnerabilidade.
- **`TrainingDummy`**: `extends Enemy`, sem código próprio.
- **Fragmento Vivo** (`LivingFragment`, `entities/enemies/living_fragment/`, valores em `@export`): estados `PATROL`, `CHASE`, `ATTACK`, `DEAD` (enum + `match`).
  - Corpo 18x24 (layer `enemies`, mask world/platforms/destructibles), gravidade padrão do projeto; 3 de vida.
  - Visual: `Visuals/AnimatedSprite2D` + `living_fragment_sprite_frames.tres`. Quadros de 64x48, olhando para a direita, pés na linha y = 44, centro em x = 32 (`centered` desligado, `offset` (-32,-45)); corpo ~30x26. Animações: `idle` 4 quadros (6 fps, loop), `walk` 6 (8 fps, loop), `attack` 8 (10 fps com durações por quadro: 0–3 = preparação 0,35 s, 4–5 = ativa 0,20 s, 6–7 = recuperação 0,40 s), `hit` 3 (12 fps), `death` 6 (10 fps).
  - Animação por estado (`_update_animation()` no fim de cada tick): `walk` com deslocamento horizontal real (`get_real_velocity()`) e `speed_scale` = velocidade / `patrol_speed` (1x na patrulha, 2x na perseguição), senão `idle`; `attack` do quadro 0 ao entrar em `ATTACK` (uma vez por investida); `hit` do quadro 0 ao receber dano, com prioridade sobre idle/walk até terminar, sem interromper a investida nem a morte. Dano fora da investida também atordoa: `hit_stun_time` = 0,25 s (15 ticks) parado, sem trocar de estado nem atacar. Animação ausente no `SpriteFrames` é ignorada.
  - Os PNGs em `sprites/` foram reduzidos por script a partir das folhas originais de 2172x724, guardadas fora do projeto (`Desktop\sprites\inimigos\`): pixels com alfa < 50% descartados, quadros detectados por colunas ocupadas, média por área com alfa binário. Cada folha veio numa escala diferente; o fator foi normalizado pela altura do quadro 0 em relação ao idle (idle 13, walk 10, attack 6,6, hit 12, death 10,2). Âncora horizontal: centro do quadro, exceto `attack`, ancorado no olho verde (a poeira deslocava o centro). Base dos pés = fundo do quadro 0 de cada folha.
  - Patrulha 30 px/s em ±48 px da origem; vira nos limites, em paredes e em bordas.
  - `DetectionArea` (círculo de 80 px, mask `player`) + linha de visão (raio dos olhos, 12 px, até 16 px acima dos pés do alvo; `sight_mask` = world + destructibles; plataformas one-way não bloqueiam). Perde o alvo acima de 128 px.
  - Perseguição 60 px/s; para a 24 px do alvo.
  - Investida (`MeleeAttack` + `living_fragment_attack.tres`): dispara com |dx| ≤ 40 e |dy| ≤ 24, no chão; preparação 0,35 s parada (o aviso é a própria animação; `show_debug` da hitbox desligado na cena), fase ativa 0,20 s a 200 px/s (até 40 px; com o alvo à frente, para a `dash_stop_distance` = 12 px dele, sem atravessar a Terra), recuperação 0,40 s parada; direção travada. Hitbox 24x12 em (12,-10) (do centro para a frente), mask `player_hurtbox`, dano 1. Recarga 1,5 s a partir do fim da recuperação. Sem dano por contato.
  - Bordas: raio para baixo logo após a borda frontal (`ground_mask` = world + platforms) em todos os estados; nunca cai.
  - Morte: para tudo, desliga o `MeleeAttack` (`PROCESS_MODE_DISABLED`), a hitbox e a detecção. Toca `death` e some ao fim dela (`animation_finished`), via `_play_death_animation()` da base `Enemy`.
- **Escavador de Cristal** (`CrystalBurrower`, `entities/enemies/crystal_burrower/`, valores em `@export`) — concluído (validado manualmente):
  - Estados `IDLE`, `PATROL`, `CHARGE`, `DASH`, `STUNNED`, `DEAD` (enum + `match`). Ciclo: `IDLE`/`PATROL` → `CHARGE` → `DASH` → `STUNNED` → `IDLE` (com recarga).
  - Corpo 32x20 em (0,-10) (layer `enemies`, mask world/platforms/destructibles), gravidade padrão; 5 de vida; Hurtbox (`CarapaceHurtbox`) 34x28 em (0,-14) (alcança o soco da Terra, y -36..-20), sem invulnerabilidade.
  - **Carapaça** (`carapace_hurtbox.gd`, `CarapaceHurtbox extends Hurtbox`, usa o gancho `_get_damage_taken`; não conhece o Escavador): golpe pelas costas = componente horizontal da trajetória (`hit_direction.x`) no mesmo sentido da orientação de `facing_node` (= `Visuals`) → dano × `back_damage_multiplier` (0,5); frontal, sem componente horizontal (`Vector2.ZERO`, vertical) ou com `shell_active` desligado → integral. Frações num acumulador (`get_pending_damage()`): 1 HP pelas costas = 0, 1, 0, 1…; 2 HP = 1. Golpe frontal não mexe no acumulador; golpes ignorados pela invulnerabilidade nem chegam ao gancho. Signal `shell_blocked` quando o golpe é absorvido por inteiro; `is_last_hit_on_shell()`. O Escavador desliga a carapaça e zera o acumulador ao entrar em `STUNNED` e ao morrer, e religa ao sair de `STUNNED`.
  - **Reação a golpes** (`hit_received` da carapaça, inclusive golpes absorvidos): em `IDLE`/`PATROL`, parado `hit_react_time` = 0,25 s (15 ticks; `is_reacting()`) e vira para o atacante (contra a trajetória), se ela tiver componente horizontal; se virar, cancela a virada pendente do fim da pausa. Durante a reação não inicia o ataque (prioridade: DEAD > CHARGE/DASH/STUNNED > reação > detecção > patrulha). Em `CHARGE`, `DASH` e `STUNNED`, dano normal (com a carapaça, exceto em `STUNNED`), sem interromper, reiniciar ou virar. Golpe fatal: sem reação.
  - **Feedback dos golpes** (`Visuals.modulate`, mesmo tween da base): frontal ou em `STUNNED` = clarão branco da base; pelas costas com dano = clarão lilás (`SHELL_HIT_COLOR`, 0,1 s); absorvido = clarão cinza-arroxeado curto (`SHELL_BLOCK_COLOR`, 0,06 s). O golpe fatal sempre usa o clarão branco (a morte some ao fim dele).
  - Visual: `Visuals/AnimatedSprite2D` + `crystal_burrower_sprite_frames.tres`, mesmo padrão do Fragmento Vivo: quadros de 64x48, olhando para a direita, pés na linha y = 44, centro em x = 32 (`centered` desligado, `offset` (-32,-45)); filtro Nearest herdado do projeto. Paleta comum de 34 cores (24 do idle + 10 extras compartilhados). Criatura ~40x33 px na pose neutra (quadro 0 de cada folha).
  - Animações (`sprites/crystal_burrower_<anim>.png`, uma folha horizontal por animação): `idle` 6 quadros (6 fps, loop, `autoplay`; nos quadros 2–3 a pata da frente se ergue), `walk` 8 (8 fps, loop), `charge` 6 (10 fps, sem loop = 0,6 s = preparação), `attack` 6 (8 fps, loop = 0,75 s = investida máxima), `hit` 4 (16 fps, sem loop = 0,25 s = reação), `stunned` 6 (6 fps, loop), `death` 8 (10 fps, sem loop = 0,8 s).
  - Troca pela máquina de estados (`_update_animation()` no fim de cada tick; o estado manda, a animação só acompanha): `IDLE`/`PATROL` = `walk` com deslocamento horizontal real (`get_real_velocity()`), senão `idle`; durante a reação a golpe, `hit` (começa no golpe, um novo golpe a recomeça; vale também para golpes absorvidos); `CHARGE` → `charge`, `DASH` → `attack`, `STUNNED` → `stunned`, cada uma do quadro 0 uma vez por entrada no estado (sem reiniciar a cada tick; o fim antecipado do DASH troca `attack` por `stunned` no mesmo tick). Golpes em `CHARGE`/`DASH`/`STUNNED` não tocam `hit`. Morte: `death` uma vez via `_play_death_animation()`; some no `animation_finished` (nada a reinicia: física desligada, golpes no corpo morto sem reação). Sem tingimento de estado (o provisório da 5A saiu); os clarões de dano continuam em `Visuals.modulate`.
  - Conversão da folha idle (fonte de IA `Desktop\sprites\inimigos\Escavador-Cristal\escavador-idle.png`, 1983x793, RGB sem alfa, fundo branco com ruído, sem grade de pixel): script `idle_build\convert_idle.gd` na mesma pasta (determinístico; prévias junto). Fundo = claros (menor canal ≥ 0,85) ligados às bordas (flood fill); quadros por colunas ocupadas, cada um limitado às próprias colunas; pés na linha mais baixa comum (y 514 da fonte); âncora horizontal pela grade de células da folha (largura / 6) + deslocamento médio das caixas (a faixa dos pés tremia, porque as pernas mudam); redução por moda, fator 8, transparente abaixo de 50% de cobertura; paleta única de 24 cores (k-means) para os 6 quadros.
  - Conversão das outras 6 folhas (mesmas características; cada uma numa escala): `anim_build\convert_burrower.gd` (README e prévias/GIFs em `anim_build\out\`; determinístico). Mesmo fundo do idle; quadros por componentes conectados + colunas (no `attack`, um quadro por corpo e a poeira solta vai para o corpo à sua direita); âncora = centro do núcleo (componentes ≥ 15% do maior, sem efeitos soltos), pés = base mais baixa dos núcleos; escala = área do quadro 0 igual à do idle (5,86 a 8,93 px da fonte por pixel); moda com 50% de cobertura no corpo e 30% em blocos só de efeito (anel do `stunned`, marcas do `hit`); paleta = 24 do idle + 10 extras compartilhados (sementes pelo ponto mais distante; com menos, o amarelo das estrelas virava laranja). Tudo coube em 64x48 sem cortes.
  - `IDLE`: parado 1 s (`idle_time`; também no início). `PATROL`: 25 px/s dentro de ±64 px da origem; ao chegar ao limite do território (para exatamente nele), a uma parede ou a uma borda (raio de `Enemy`, `ground_mask` = world + platforms), entra em `IDLE` e só vira ao fim da pausa. No ar não anda (cai reto).
  - Detecção frontal: `Visuals/DetectionArea` (retângulo 128x40 de x 0 a 128, pés a 40 px acima; mask `player`; vira junto) + linha de visão (`eye_height` 10, `target_sight_height` 16, `sight_mask` = world + destructibles). Atualizada no fim de cada tick em `IDLE`/`PATROL` (`get_detected_target()`, `is_target_detected()`; `null` nos outros estados). A lista de sobreposições da `Area2D` atualiza no passo de física seguinte (~2 ticks de atraso ao teleportar a Terra).
  - Ataque (`MeleeAttack` + `crystal_burrower_dash.tres`; cada fase é um estado): dano 1; `windup_time` 0,6 s = `CHARGE`, `active_time` 0,75 s = duração máxima do `DASH`, `recovery_time` 1,2 s = `STUNNED`. `dash_speed` 180 px/s (alcance teórico 135 px); `cooldown_time` 1 s. Hitbox `Visuals/Hitbox` 28x14 em (4,-8) (baixa, cobre o corpo: x -10..18, y -15..-1; a Terra passa por cima pulando), mask `player_hurtbox`, `show_debug` desligado. Sem dano por contato.
  - `CHARGE`: no fim do tick, logo após a detecção (que já confirmou a linha de visão), se a recarga terminou e está no chão: `try_attack()`, vira para a Terra uma vez e trava a direção; parado 0,6 s (36 ticks), hitbox desligada. Entra em `DASH` no tick em que o `MeleeAttack` liga a hitbox.
  - `DASH`: 180 px/s na direção travada, atravessando a Terra (corpos não colidem); um acerto por investida (`Hitbox`). Termina por tempo (o `MeleeAttack` desliga a hitbox e começa a recuperação) ou antes: borda à frente (`_has_ground_ahead` com o passo do tick, antes de mover) ou parede à frente (depois do `move_and_slide`) chamam `finish_active()` → hitbox desligada no mesmo tick (a `Hitbox`, filha, roda depois do Escavador) e recuperação completa a partir dali.
  - `STUNNED`: parado 1,2 s (72 ticks, também após parede/borda), sem detecção, sem virar, com gravidade; carapaça desligada (dano integral por qualquer lado). Ao fim do `MeleeAttack` volta a `IDLE` (pausa normal) e só então começa a recarga de 1 s (`is_attack_ready()`); na recarga patrulha e detecta, mas não ataca.
  - Morte (provisória, sem animação), em qualquer estado: `DEAD`, velocidade zero, física desligada, `MeleeAttack` em `PROCESS_MODE_DISABLED`, hitbox e detecção desligadas, reação cancelada, carapaça desligada e acumulador zerado (golpes no corpo morto não geram `shell_blocked` nem feedback), cristais normais; some depois do piscar da base `Enemy`.

### Cenário

- **Terreno em `TileMapLayer`** (uma camada `Terrain` por sala, com chão, paredes e plataformas). Destrutíveis continuam fora do tilemap (ver "Regras de design").
- **Reino das Profundezas** (`depths`, região da Terra):
  - **Atlas** `depths_terrain.png`: 8x4 células de 16x16 (128x64), paleta fixa de 17 cores (`depths_palette.png`; a cor 16, laranja, é reservada aos props). Mapa das células: linha 0 = canto ↖, topo, canto ↗, cantos internos ↖/↗ (diagonal vazia), topo v1/v2, bloco 1x1; linha 1 = lateral ←, centro, lateral →, cantos internos ↙/↘, centro v1–v3; linha 2 = canto ↙, base, canto ↘, faixa horizontal (← · →), base v1, (7,2) vazia; linha 3 = faixa vertical (↑ · ↓), plataforma (← · →), plataforma · v1, plataforma 1x1. Variações têm a mesma silhueta e as mesmas bordas da peça base.
  - **TileSet** `depths_tileset.tres`: camada de física 0 = layer `world` (polígono 16x16 nos 26 sólidos); camada 1 = layer `platforms` (faixa one-way de 16x8 no topo das 5 plataformas, mesma espessura da plataforma do MovementLab; o desenho do corpo tem 13 px). Máscaras 0.
  - **Terrain sets:** 0 = `Rocha` (cantos e lados), 1 = `Plataforma` (só lados). Variações com probabilidade 0,15 (base 1,0). Pintar com o pincel de terreno do editor (ou `set_cells_terrain_connect`).
  - **Regra deste primeiro conjunto** (não vale para o jogo todo): massas sólidas com espessura mínima de 2 tiles e faixas de 1 tile isoladas, inclusive na diagonal. Junções em T e dois cantos internos no mesmo tile não têm peça (o pincel escolhe a mais próxima). Sem rampas.
  - Bordas da sala: pintar uma moldura de rocha 1 tile fora dos limites da câmera, para que as bordas visíveis usem peças internas.
- **Plataformas one-way e altura da Terra:** o pulo sobe 56 px e a Terra tem 46 px de altura, então uma plataforma alcançável a partir do chão fica na altura da cabeça de quem anda embaixo. No level design, plataformas sobre chão percorrível ficam a 3 tiles ou mais e são alcançadas a partir de pontos elevados.
- **Fundo com parallax** (`world/levels/depths/backgrounds/depths_parallax.tscn`, cena reutilizável sem script): raiz `Node2D` com três `Parallax2D` (`Far`, `Mid`, `Near`, nessa ordem), cada um com um `Sprite2D` (`centered` desligado, em (0,0)). Sem colisões. Cada sala instancia a cena como **primeiro filho**, antes do `Terrain`: a ordem na árvore põe o fundo atrás de tudo (`z_index` 0 em todos os nós).
  - | Camada | Textura | `scroll_scale` | `repeat_size` | Pixel da arte |
    |---|---|---|---|---|
    | `Far` (opaca: teto distante, névoa, montanhas) | `depths_bg_far.png` 852x360 | (0,15, 0) | (852, 0) | 4x4 px |
    | `Mid` (arcos, pilares, estalactites) | `depths_bg_mid.png` 1110x360 | (0,40, 0) | (1110, 0) | 6x6 px |
    | `Near` (rochas e raízes só no alto e embaixo) | `depths_bg_near.png` 1056x360 | (0,70, 0) | (1056, 0) | 6x6 px |
  - `repeat_times` 1 (padrão) basta porque cada textura tem pelo menos 640 px de largura. `scroll_scale.y` = 0: as camadas ficam presas à tela na vertical e cobrem os 360 px em salas de qualquer altura. Parallax vertical exigiria imagens com altura 360 + ⌈escala y × (altura da sala − 360)⌉. Comportamento conferido no 4.7.2 com quadros renderizados: na tela, a camada fica deslocada em −(borda esquerda da câmera × escala) módulo largura; a câmera já vem limitada pelos limites da sala; nenhuma coluna fica vazia, nem com a câmera em ±20 000 px.
  - Paleta (`depths_bg_palette.png`, 4 cores por camada, todas mais escuras que o terreno; luminância máxima 0,082): far `#0d1524 #192841 #263c5c #34527a`; mid `#0e222c #143442 #1b4554 #1f5163`; near `#06090f #0b121b #111a26 #1c1520` (a última é a das raízes).
  - Zona central limpa: em y 96–288 a camada próxima ocupa no máximo 5% (hoje 3,2%) e a intermediária no máximo 40% (hoje 23%).
  - Arte: imagens de IA tileáveis na largura inteira, convertidas para a grade real da arte (213x90, 185x60, 176x60 pixels) e ampliadas por fator inteiro (x4/x6). Por isso o fundo tem pixels maiores que o terreno e os personagens (1 px), escolha aprovada. Larguras = largura inteira da arte original, para manter a emenda natural (sem corte nem reparo).
  - Reconstrução e instalação: `Desktop\sprites\fase_terra\parallax_build\` (README). `build_scene.gd` sobrescreve `depths_parallax.tscn`.
- **Props decorativos** (`world/props/depths/`): só visuais, sem colisões, dano, scripts ou animação; uma cena por prop (raiz `Sprite2D`, `centered` desligado, `offset` = âncora, filtro herdado, Lossless sem mipmaps), uma pasta por grupo. Gerados por IA e convertidos por script fora do projeto (`Desktop\sprites\fase_terra\props_build\`, README).
  - **Âncora:** props de chão no centro da base (`offset` (−w/2, −h)), pendentes no centro do topo (`offset` (−w/2, 0)). A base (ou o topo) real da rocha fica na última (ou primeira) linha da PNG e o desenho é centrado na largura em pixels inteiros. Com a grade do editor em 8 ou 16 px, o prop encaixa na borda do tile.
  - **Na sala:** nó `Props` (`Node2D`) entre `Terrain` e `Enemies` (ordem: `Background`, `Terrain`, `Props`, `Enemies`, `Terra`). Ninguém usa `z_index`, então a ordem na árvore põe Terra, inimigos e golpes por cima (a onda sísmica, que é `top_level`, também; conferido com quadro renderizado). Instâncias só sobrescrevem a posição, como o resto da sala.
  - **Regras de posicionamento:** cristais pequenos perto do caminho; médios em bordas e áreas secundárias; grandes junto a paredes ou em lugares pouco percorridos, nunca no chão ou nos degraus do caminho principal (trajeto da onda sísmica); pendentes presos ao teto; nenhum prop alto no início da Terra; nenhum pixel dentro de tiles sólidos.
  - **Paleta dos props** (`depths_props_palette.png`, 24 cores): as 17 do terreno + `#8a3a10 #ffc85a #fff1c2` (âmbar) + `#2a2628 #47403d #6b625b #958a7e` (pedra das ruínas, para os próximos grupos).
  - **Cristais** (`crystals/`, 10 cores: contorno `#130f12`; rocha `#221817 #43261d #5a3321 #794526 #98592c`; cristal `#8a3a10 #fb9524 #ffc85a #fff1c2`):
    | Cena (raiz) | Caixa | Arte | `offset` |
    |---|---|---|---|
    | `crystal_small` (`CrystalSmall`) | 16x24 | 16x17 | (−8, −24) |
    | `crystal_medium` (`CrystalMedium`) | 32x32 | 30x31 | (−16, −32) |
    | `crystal_large` (`CrystalLarge`) | 48x56 | 48x53 | (−24, −56) |
    | `crystal_ceiling` (`CrystalCeiling`, pendente) | 40x48 | 34x44 | (−20, 0) |
  - A folha da IA tinha pixels de arte não quadrados (~7,44 x 6,60 px); a conversão leva 1 pixel de arte a 1 pixel quadrado, sem redimensionar por fração, então os cristais ficaram ~12% mais altos que na folha (aprovado). Contornos em `#130f12` e `#221817` e pixels isolados da arte foram preservados.
  - **Vegetação** (`vegetation/`; cores por sprite, todas da paleta de 24): musgos `#221817 #301d18 #1a1e0c #3f4612 #646a12 #878b13` (sem `#aead19`, para ficarem mais escuros que o musgo dos tiles); raízes `#130f12 #221817 #301d18 #43261d #5a3321 #794526 #98592c`; fungos `#221817 #43261d #5a3321 #98592c #c08550 #e3a86d #3f4612 #646a12`.
    | Cena (raiz) | Caixa | Arte | Âncora | `offset` |
    |---|---|---|---|---|
    | `moss_hanging` (`MossHanging`) | 48x32 | 45x25 | teto | (−24, 0) |
    | `root_short` (`RootShort`) | 32x48 | 25x42 | teto | (−16, 0) |
    | `root_long` (`RootLong`) | 48x64 | 45x63 | teto | (−24, 0) |
    | `moss_tuft` (`MossTuft`) | 32x16 | 26x9 | chão | (−16, −16) |
    | `fungi_small` (`FungiSmall`) | 24x24 | 22x19 | chão | (−12, −24) |
    | `fungi_tall` (`FungiTall`) | 24x32 | 21x31 | chão | (−12, −32) |
  - Regras da vegetação na sala: apoio no **pixel opaco do atlas** (não só na célula; a face de baixo das plataformas one-way é irregular: corpo até a linha 8–10 do tile, gotas até a 15); sobreposição decorativa com o terreno permitida, mas sem cobrir o topo do chão (4 px) nem a faixa one-way (8 px); peças penduradas deixam 54 px livres (Terra de pé + 8) sobre a superfície abaixo; no caminho principal só vegetação de até 20 px, salvo encostada numa parede (até 4 px); nada alto no início da Terra. A folha da IA veio ~40% maior que o pedido (grade quase quadrada, 7,34 x 7,27 px): caixas finais aumentadas, arte 1:1 sem corte (aprovado).
  - Catálogo aprovado para os próximos grupos (implementados um de cada vez): rochas (`pebbles`, `boulder`, `stalagmite_small/large`, `stalactite`, `crack_small/large`), ruínas (`pillar_broken_short/tall`, `pillar_fallen`, `carved_stone`, `carved_fragment`).
- **Sala de teste** `world/levels/depths/depths_test_room.tscn` (48x23 tiles, 768x368): `Background` (fundo com parallax), `Terrain`, `Props` (8 cristais: grande sobre o bloco flutuante, médios sobre a faixa e no canto direito, pequenos no chão, no primeiro degrau e ao pé do terceiro, dois pendentes no teto; 8 de vegetação: tufos no chão esquerdo e no 2º degrau, fungo pequeno sob a faixa, fungo alto junto à face do 1º degrau, musgo pendente sob o bloco e sob a plataforma larga, raiz curta no teto e raiz longa no teto à direita), `Enemies` (2 Fragmentos Vivos, ambos no chão: `LivingFragmentFloor` em (648, 320) e `LivingFragmentPlatform` em (302, 316), ao pé do 1º degrau — o nome do nó vem da posição antiga, na plataforma larga) e `Terra` com `Camera2D` (limites = sala). Instâncias só sobrescrevem a posição. Contém chão, paredes, degraus de 1–3 tiles, bloco flutuante, faixa, coluna, saliência no teto e plataformas (larga, 1x1, alta).

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
