import { createRouter, createWebHashHistory } from 'vue-router';
import Home from '../views/home/Home.vue';

const routes = [
  {
    path: '/',
    name: 'home',
    component: Home,
  },
  {
    path: '/users',
    name: 'users',
    component: () => import('../views/users/Users.vue'),
  },
  {
    path: '/configuration',
    name: 'configuration',
    component: () => import('../views/configuration/Configuration.vue'),
  },
  {
    path: '/deployment',
    name: 'deployment',
    component: () => import('../views/deployment/Deployment.vue'),
  },
  {
    path: '/administration/server-log',
    name: 'server-log',
    component: () => import('../views/administration/ServerLogViewer.vue'),
  },
  {
    path: '/administration/worker-count',
    name: 'worker-count',
    component: () => import('../views/administration/WorkerCount.vue'),
  },
  {
    path: '/administration/max-transaction-size',
    name: 'max-transaction-size',
    component: () => import('../views/administration/MaxTransactionSize.vue'),
  },
  {
    path: '/administration/server-log-level',
    name: 'server-log-level',
    component: () => import('../views/administration/ServerLogLevel.vue'),
  },
  {
    path: '/administration/config-exchange',
    name: 'config-exchange',
    component: () => import('../views/administration/ConfigExchange.vue'),
  },
  {
    path: '/information',
    name: 'information',
    component: () => import('../views/information/InstanceInfos.vue'),
  },
];

const router = createRouter({
  history: createWebHashHistory(),
  routes,
});

export default router;
