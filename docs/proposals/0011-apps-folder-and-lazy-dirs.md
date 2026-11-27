# 0011 — Projetos HTTP em `apps/` e pastas criadas sob demanda

Status: **implementada**

## Problema

- O `boto new` cria `apps/`, `libs/`, `services/` e `workers/`, cada uma com
  um `.keep`, mesmo sem nenhum projeto dentro. A solution nova nasce com
  quatro pastas vazias.
- A pasta `services/` separa `webapi` e `microservice` de `web` e `spa`
  (`apps/`) sem ganho real. Os quatro são projetos HTTP que o `boto run`
  sobe, e o tipo já fica declarado no Botofile (`template:`).

## API pública

### Estrutura de uma solution

```
loja/
├── Botofile
├── apps/          # webapi, microservice, web e spa (criada no primeiro boto add de um desses)
├── libs/          # library (criada no primeiro boto add library)
└── workers/       # worker (criada no primeiro boto add worker)
```

| Template | Pasta |
|---|---|
| `webapi`, `microservice`, `web`, `spa` | `apps/<nome>` |
| `library` | `libs/<nome>` |
| `worker` | `workers/<nome>` |

- **`boto new`:** cria só `Botofile`, `Gemfile`, `.ruby-version` e
  `.gitignore`. Não cria pastas de projeto.
- **`boto add`:** cria a pasta do tipo junto com o projeto, como já acontece
  com `apps/<nome>`.
- O Botofile não muda: a pasta continua derivada do template.

### Solution antiga, com `services/`

Um projeto `webapi` ou `microservice` com o código em `services/<nome>` e sem
`apps/<nome>` vira erro claro, em vez de o Boto carregar uma pasta vazia em
silêncio:

```
boto: project "pedidos" is in services/pedidos; HTTP projects now live in apps/.
Fix: git mv services/pedidos apps/pedidos
```

A checagem roda no `Boto::Boot` (`boto run`, `boto openapi` e os testes do
projeto) e no carregamento da solution pelo CLI. Assim o `boto check`
também não passa batido.

## Estrutura

```
gems/boto-rb/lib/boto/solution/project.rb        # TEMPLATE_DIRS: webapi/microservice -> apps
gems/boto-rb/lib/boto/solution/solution.rb       # legacy_paths(root): projetos ainda em services/
gems/boto-rb/lib/boto/solution/boot.rb           # erro com o Fix antes de carregar
gems/boto-rb-cli/lib/boto/cli/command.rb         # mesmo erro ao carregar a solution
gems/boto-rb-cli/templates/solution/             # sem apps/ libs/ services/ workers/
gems/boto-rb/test/fixtures/*/services -> apps    # fixtures movidas
CLAUDE.md                                        # seção "Estrutura de pastas"
```

## Fase do roadmap

Ajuste da Fase 0 (estrutura da solution). Entra antes do template
`microservice`, que já nasce em `apps/`.

## Performance

Não muda nada por request. No boot, a checagem só testa a existência de
algumas pastas.

## Segurança

Não há impacto.

## Compatibilidade

- **Quebra (pré-1.0, versão minor):** solutions com projetos em `services/`
  precisam mover as pastas. A mensagem de erro traz o comando.
- **CHANGELOG:** `Changed` (projetos HTTP em `apps/` e pastas criadas sob
  demanda), com a migração (`git mv services/<nome> apps/<nome>` para cada
  projeto).

## Testes planejados

- **Project:** `webapi` e `microservice` ficam em `apps/`, `library` em
  `libs/` e `worker` em `workers/`.
- **`boto new`:** não cria `apps/`, `libs/`, `services/` nem `workers/`.
- **`boto add`:** `boto add webapi api` cria `apps/api`, e
  `boto add library dominio` cria `libs/dominio`.
- **Legado:**
  - um projeto em `services/` sem `apps/` faz o Boot e os comandos do CLI
    falharem com a mensagem e o `Fix`;
  - com a pasta movida, tudo funciona.
- **Fixtures e testes:** todos atualizados para `apps/`.

## Alternativas descartadas

- **Aceitar `services/` e `apps/` ao mesmo tempo:** duas convenções para a
  mesma coisa, e a dúvida de onde cada projeto está.
- **`path:` opcional no Botofile:** flexibilidade que ninguém pediu, e que
  enfraquece a convenção.
- **Migrar as pastas automaticamente:** o CLI moveria arquivos do usuário sem
  ele pedir. Melhor mostrar o comando e deixar a decisão com ele.
