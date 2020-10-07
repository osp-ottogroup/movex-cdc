import Vue from 'vue';
import Buefy from 'buefy';
import App from './App.vue';
import router from './router';

Vue.use(Buefy, {
  defaultTooltipType: 'is-light',
  defaultTooltipDelay: 1000,
});

Vue.config.productionTip = false;

new Vue({
  router,
  render: (h) => h(App),
}).$mount('#app');
