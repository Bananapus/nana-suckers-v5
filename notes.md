## CCIP Sucker Language

### Deployer

- It looks like the "layer-specific configurator" is only respected by the `CCIPSuckerDeployer`. Can we remove it from the base/arb/optimism suckers?
- Why is `_admin` (in constructor args for deployer, formerly `_configurator`) prefixed with an underscore?
- Do I understand correctly that each deployer only deploys CCIP suckers for a single lane? Why?
- Should it be possible to call `JBCCIPSuckerDeployer.setChainSpecificConstants(…)` multiple times?
