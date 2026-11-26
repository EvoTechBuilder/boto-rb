---
name: new-plugin
description: Use ao criar ou alterar um plugin do Boto (auth, cors, rate_limit, hosts, sessions, csrf, secure_headers, telemetry ou outro ligado via app.use). Cobre middleware, ordem, skip no endpoint, testes e CHANGELOG.
---

# Criar ou alterar um plugin

1. Para um plugin novo, use antes a skill `propose-api`.
2. Implemente o plugin como middleware Rack em
   `gems/boto/lib/boto/plugins/<nome>.rb`, sob `Boto::Plugins::<Nome>`.
3. Registre o plugin para que `app.use :<nome>, **opcoes` funcione no
   `config/app.rb`.
4. Valide as opções no boot e falhe com mensagem clara se estiverem erradas.
5. Se for um plugin de segurança, coloque-o na posição certa da ordem fixa
   (hosts -> secure_headers -> sessions -> csrf -> auth -> rate_limit) e
   atualize essa lista no CLAUDE.md.
6. Dê suporte a `skip :<nome>` no `Boto::Endpoint`. A exceção vale só para
   aquele endpoint.
7. Se o plugin fizer parte do default de algum template, ligue-o no
   `config/app.rb` desse template.
8. Testes com `Rack::MockRequest`:
   - plugin ligado;
   - endpoint com `skip`;
   - opções inválidas falhando no boot;
   - casos de ataque (veja `.claude/rules/security.md`).
9. Se o plugin roda em todo request, use a skill `benchmark`.
10. Registre a mudança no `CHANGELOG.md`, na seção `Unreleased`.
