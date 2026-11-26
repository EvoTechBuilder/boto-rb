---
name: commit
description: Use para criar qualquer commit no repositório do Boto. Segue Conventional Commits 1.0.
---

# Commit no padrão Conventional Commits

## Formato

```
<type>(<scope>): <description>

<body opcional: o porquê da mudança>

<footer opcional: BREAKING CHANGE: ..., Refs: ...>
```

- **type**: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `build`, `ci`,
  `chore`, `style` ou `revert`.
- **scope**: `boto`, `cli`, `telemetry`, `templates`, `benchmarks`, `docs`,
  `examples` ou `ci`. Se a mudança cobre vários escopos, omita o scope.
- **description**: em inglês, no imperativo, minúscula, sem ponto final, com
  até 72 caracteres. Exemplo: `feat(boto): add radix router`.
- **Breaking change**: use `!` depois do scope (`feat(boto)!: ...`), um
  footer `BREAKING CHANGE: <o que quebra e como migrar>` e uma entrada no
  CHANGELOG.

## Passos

1. Se a pasta não for um repositório git, pergunte antes de rodar `git init`.
2. Rode os testes afetados. Não faça commit com teste falhando.
3. Rode `git status` e `git diff --staged`. Adicione só os arquivos da
   mudança, pelo nome, sem `git add -A`.
4. Nunca faça commit de segredos: `master.key`, `.env` ou credentials
   descriptografadas. O `credentials.yml.enc` pode entrar.
5. Um commit por mudança lógica. Na skill `implement-feature`, isso significa
   um commit por task.
6. Não faça push sem o usuário pedir.
