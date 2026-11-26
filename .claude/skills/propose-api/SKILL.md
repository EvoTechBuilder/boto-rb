---
name: propose-api
description: Use antes de implementar algo grande no Boto (componente novo do core, comando do CLI, plugin, template, mudança na DSL do Botofile ou do Boto::Endpoint). Escreve a proposta de estrutura e API pública e para até ela ser revisada.
---

# Propor estrutura e API pública

O CLAUDE.md exige revisão da API antes de implementar algo grande. Siga estes
passos.

1. Leia as seções do CLAUDE.md ligadas ao tema e o código que já existe na
   área.
2. Escreva `docs/proposals/NNNN-<nome>.md` (NNNN é o próximo número livre) com:
   - **Problema**: o que falta hoje, em poucas linhas.
   - **API pública**: exemplos de código como o usuário do Boto vai
     escrever (Botofile, endpoint, `config/app.rb` ou comando do CLI).
     Exemplos primeiro, assinaturas depois.
   - **Estrutura**: os arquivos e classes que vão ser criados e em qual gem.
   - **Fase do roadmap** em que a proposta entra.
   - **Performance**: o que acontece no boot e o que acontece por request.
   - **Segurança**: o que pode ser explorado e qual o default.
   - **Compatibilidade**: impacto em semver e o que entra no CHANGELOG.
   - **Testes planejados**.
   - **Alternativas descartadas**: uma linha cada, com o motivo.
3. Mostre a proposta ao usuário e pare. Não escreva código de implementação
   até a aprovação.
4. Depois de aprovada, implemente seguindo a proposta. Se a implementação
   precisar se desviar dela, atualize o arquivo e avise o usuário.
