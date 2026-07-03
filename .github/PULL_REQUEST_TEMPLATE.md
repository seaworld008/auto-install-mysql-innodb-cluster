## Summary

- 

## Type of change

- [ ] Documentation
- [ ] Bug fix
- [ ] New feature
- [ ] CI / validation
- [ ] Configuration or inventory
- [ ] Operational workflow

## Testing

- [ ] `git diff --check`
- [ ] `bash -n deploy.sh validate_deployment.sh scripts/*.sh`
- [ ] `ansible-playbook -i inventory/hosts.yml playbooks/site.yml --syntax-check`
- [ ] `ansible-playbook -i inventory/hosts-ha-reference.yml playbooks/site.yml --syntax-check`
- [ ] `ansible-playbook -i inventory/hosts-with-dedicated-routers.yml playbooks/site.yml --syntax-check`
- [ ] Real environment validation, if applicable

## Checklist

- [ ] I have not committed real passwords, tokens, private keys, or production-only identifiers.
- [ ] I updated README or runbooks if behavior changed.
- [ ] I kept `inventory/group_vars/all.yml` as the runtime source of truth.
- [ ] I did not introduce a parallel deployment flow.
- [ ] I documented any required manual verification.

## Related issues

Closes #
