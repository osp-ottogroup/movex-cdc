import Vue from 'vue';
import VueRouter from 'vue-router';
import Home from '../views/home/Home.vue';

Vue.use(VueRouter);

const routes = [
  {
    path: '/',
    name: 'home',
    component: Home,
  },
  {
    path: '/users',
    name: 'users',
    // route level code-splitting
    // this generates a separate chunk (about.[hash].js) for this route
    // which is lazy-loaded when the route is visited.
    component: () => import(/* webpackChunkName: "about" */ '../views/users/Users.vue'),
  },
  {
    path: '/configuration',
    name: 'configuration',
    component: () => import(/* webpackChunkName: "about" */ '../views/configuration/Configuration.vue'),
  },
  {
    path: '/deployment',
    name: 'deployment',
    component: () => import(/* webpackChunkName: "about" */ '../views/deployment/Deployment.vue'),
  },
  {
    path: '/administration/server-log',
    name: 'server-log',
    component: () => import(/* webpackChunkName: "about" */ '../views/administration/ServerLogViewer.vue'),
  },
  {
    path: '/administration/worker-count',
    name: 'worker-count',
    component: () => import(/* webpackChunkName: "about" */ '../views/administration/WorkerCount.vue'),
  },
  {
    path: '/administration/server-log-level',
    name: 'server-log-level',
    component: () => import(/* webpackChunkName: "about" */ '../views/administration/ServerLogLevel.vue'),
  },
  {
    path: '/information',
    name: 'information',
    component: () => import(/* webpackChunkName: "about" */ '../views/information/InstanceInfos.vue'),
  },
];

const router = new VueRouter({
  routes,
});

export default router;
