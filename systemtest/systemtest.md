#### Setup
`npm install`

This will install anything that is needed from cypress.

Trixx should be running and its URL should be used as baseURL in the cypress.json config.

#### Run Cypress UI
`./node_modules/.bin/cypress open`

#### Run Systemtests
`./node_modules/.bin/cypress run`
will run the tests headless in electron/chromium. Add the option `--headed` to show Electron for execution.

`./node_modules/.bin/cypress run --headless --browser chrome`
will run the tests headless in chrome. By default, chrome would execute *headed*.

#### Parallel execution
Parallel execution is only possible when using the cypress dashboard to record the tests. There is a limit of 500 monthly recordings for the free tier.

Possible workarounds:
* https://sorry-cypress.dev/ (legality unclear, questionable i think)
* fixed split via CI pipeline
```
 1-job:
   stage: acceptance-test
   script:
     - npm install
     - npm i -g wait-on
     - wait-on -t 60000 -i 5000 http://yourbuild
     - npm run cypress -- --config baseUrl=http://yourbuild --spec ./**/yourspec1

 2-job:
   stage: acceptance-test
   script:
     - npm install
     - npm i -g wait-on
     - wait-on -t 60000 -i 5000 http://yourbuild
     - npm run cypress -- --config baseUrl=http://yourbuild --spec ./**/yourspec2
```