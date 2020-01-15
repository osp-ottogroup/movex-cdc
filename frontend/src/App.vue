<template>
  <div id="app">
    <template v-if="loggedIn">
      <app-header />
      <router-view id="router-view"/>
      <app-footer />
    </template>
    <template v-else>
      <b-modal
        :can-cancel="false"
        :active="true"
        :trap-focus="true"
        :width="400"
      >
        <login-form @login="onLogin" />
      </b-modal>
    </template>
  </div>
</template>

<script>
import AppHeader from './components/AppHeader.vue';
import AppFooter from './components/AppFooter.vue';
import LoginForm from './components/LoginForm.vue';
// import LoginService from './services/LoginService';

export default {
  name: 'App',
  components: {
    AppHeader,
    AppFooter,
    LoginForm,
  },
  data() {
    return {
      loggedIn: false,
    };
  },
  // async created() {
  //   this.loggedIn = await LoginService.checkLogin();
  // },
  methods: {
    onLogin() {
      this.loggedIn = true;
    },
  },
};
</script>

<style lang="scss">
$footer-padding: 0.3rem 0;

@import './app.scss';

#app {
  display: flex;
  min-height: 100vh;
  flex-direction: column;
}

#router-view {
  flex: 1;
}
</style>
