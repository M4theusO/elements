# ELEMENTS

Jogo indie 2D side-scrolling, estilo Metroidvania, em pixel art: exploração, combate e progressão de habilidades num universo de fantasia elemental.

| Elemento | Protagonista |
|----------|--------------|
| Terra    | Terra        |
| Água     | Aqua         |
| Fogo     | Ignis        |
| Ar       | Aeris        |

> **Estado:** protótipo em desenvolvimento (Marco 1, com a Terra). Já existem movimentação, pulo, combate básico, o Punho Sísmico e o primeiro inimigo (Fragmento Vivo). Os outros protagonistas ainda não foram implementados.

## Stack

- **Godot 4.7.2 Stable** (edição Standard), **GDScript**
- Renderizador **Compatibility** (WebGL 2)
- Plataforma principal: **Web (HTML5)**, publicada no itch.io; Windows no futuro
- Resolução interna 640x360, exibida em 1280x720 (escala inteira 2x)

## Como rodar

1. Instale a [Godot 4.7.2 Stable](https://godotengine.org/download) (edição Standard, não .NET).
2. Na Godot, use **Importar** e selecione o `project.godot` desta pasta.
3. Pressione **F5**. A cena principal, por enquanto, é o laboratório de movimento (`tests/movement_lab/movement_lab.tscn`), com degraus, plataforma one-way, bonecos de treino e inimigos.

## Controles

| Ação | Teclado (A) | Teclado (B) | Gamepad |
|---|---|---|---|
| Mover | A / D | ← / → | Analógico esquerdo / D-pad |
| Pular | K ou Espaço | Z | A |
| Atacar | J | X | X |
| Habilidade (Punho Sísmico) | L | C | Y |
| Interagir | E | ↑ | B |
| Pausar | Esc ou P | Esc ou P | Start |

No navegador, clique no jogo antes de jogar para ele receber o teclado. Gamepads só são detectados depois que algum botão é pressionado.

## Testes automatizados

Os testes rodam sem abrir o editor. Na raiz do projeto, troque `godot` pelo caminho do executável da Godot 4.7.2:

```sh
godot --headless --path . -s res://tests/animation/player_animation_test.gd
godot --headless --path . -s res://tests/combat/combat_test.gd
godot --headless --path . -s res://tests/combat/seismic_fist_test.gd
godot --headless --path . -s res://tests/enemies/living_fragment_test.gd
```

Cada teste imprime as verificações e termina com código de saída 0 quando tudo passa.

## Estrutura

Organização por funcionalidade: cada personagem, inimigo ou fase guarda na própria pasta sua cena, script, sprites e dados.

```
core/        código genérico e reutilizável (componentes, resources, utilitários)
entities/    personagens e inimigos
world/       fases, tilesets e objetos de cenário
ui/          HUD, menus e tema
assets/      áudio, fontes e shaders compartilhados
main/        cena de entrada e fluxo entre telas
tests/       cenas de teste e testes automatizados
```

As diretrizes completas do projeto (arquitetura, convenções de código, colisões, combate, formato das animações e regras para a Web) estão no [CLAUDE.md](CLAUDE.md).
