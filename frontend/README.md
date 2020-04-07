# app

## Project setup
```
npm install
```

### Compiles and hot-reloads for development
```
npm run serve
```

### Compiles and minifies for production
```
npm run build
```

### Run your unit tests
```
npm run test:unit
```

### Run your end-to-end tests
```
npm run test:e2e
```

### Lints and fixes files
```
npm run lint
```

### Customize configuration
See [Configuration Reference](https://cli.vuejs.org/config/).

## Development with docker and docker-compose
run front- and backend services
```shell script
# execute in from project root
docker-compose -f docker/dev_docker-compose.yml up -d
```

show logs of running services
```shell script
# execute in from project root
docker-compose -f docker/dev_docker-compose.yml logs -f
```