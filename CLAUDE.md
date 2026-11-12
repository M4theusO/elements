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

- Projeto **em fase inicial**: até o momento existe apenas este CLAUDE.md.
- Existem apenas: `project.godot` configurado (seção 9), a estrutura de pastas vazia (seção 7, com `.gitkeep`) e o repositório Git local.
- Nenhuma cena, script, asset, autoload ou sistema foi criado ainda.
- **Não presuma que algo existe.** Antes de referenciar uma cena, script, asset, input action, layer de física ou autoload, verifique no repositório. Se não existir, informe e pergunte antes de criar.

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
- Stretch: mode `viewport`, aspect `keep`, scale mode `integer` — o jogo é renderizado em 640x360 e ampliado apenas por múltiplos inteiros; sobra de tela vira barras pretas.
- Filtro de textura padrão: **Nearest**.

Notas Web: no navegador, o tamanho do canvas é definido pela página/iframe (o override de janela não se aplica). No itch.io, configurar o embed em 1280x720 para escala 2x exata. A política de redimensionamento do canvas (`Canvas Resize Policy`) será definida ao criar o preset de exportação Web.

Itens a serem decididos e registrados aqui quando forem criados — **não criar sem aprovação**:

- Input Map (nomes das ações), respeitando as restrições de teclado do navegador (seção 2.1).
- Layers de colisão física (nome e número de cada layer).
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
