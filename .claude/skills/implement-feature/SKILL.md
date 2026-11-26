---
name: implement-feature
description: Use sempre que for implementar uma feature, correção ou mudança no Boto que vá além de um ajuste trivial. Cria o plano, divide em tasks e executa cada task num subagente task-runner com o modelo Haiku.
---

# Implementar uma feature

Nenhuma linha de implementação é escrita antes do plano aprovado.

## 1. Entender

- Leia o CLAUDE.md e o código da área afetada.
- Se a feature cria ou muda API pública (DSL, classes do core, comandos do
  CLI, plugins, templates), use antes a skill `propose-api` e espere a
  aprovação.

## 2. Planejar

Escreva `docs/plans/YYYY-MM-DD-<feature-name>.md`, com nome em inglês, contendo:

- **Objetivo**: uma ou duas frases.
- **Fora de escopo**: o que fica de fora de propósito.
- **Tasks numeradas.** Para cada uma:
  - objetivo;
  - arquivos a criar ou alterar (caminhos exatos, em inglês);
  - testes que provam que a task está pronta;
  - dependências (quais tasks precisam terminar antes);
  - comando para rodar os testes.

Como dimensionar a task: um subagente Haiku precisa conseguir terminá-la só
com o brief. Ela mexe em poucos arquivos e entrega código com testes
passando. Se precisar de contexto que não cabe no brief, divida a task.

Mostre o plano e espere a aprovação do usuário.

## 3. Executar com subagentes

- Para cada task, chame o `Agent` com `subagent_type: "task-runner"` e
  `model: "haiku"`.
- O prompt é o brief da task, completo e autocontido. O subagente não vê esta
  conversa, então o brief inclui:
  - objetivo;
  - arquivos;
  - trechos relevantes do CLAUDE.md e das rules;
  - testes esperados;
  - comando de teste;
  - critério de pronto.
- Tasks sem dependência entre si e sem arquivos em comum rodam em paralelo, na
  mesma mensagem. As demais rodam em sequência.

## 4. Revisar cada task

- Leia o diff e rode os testes com YJIT ligado e desligado.
- Confira as rules (`clean-code`, `tests`, `performance`, `security`).
- Se a task falhar, devolva o problema ao mesmo subagente com `SendMessage`.
  Depois de duas tentativas sem sucesso, corrija você mesmo ou divida a task
  de novo.
- Com a task aprovada, faça um commit por task usando a skill `commit`.

## 5. Fechar

- Rode a suíte completa.
- Se mexeu no caminho quente, use a skill `benchmark`.
- Atualize o `CHANGELOG.md` se a API pública mudou.
- Marque o plano como concluído e resuma em português o que foi entregue e o
  que ficou pendente.
