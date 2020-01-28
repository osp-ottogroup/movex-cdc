<template>
  <div id="app">
    <template v-if="loggedIn">
      <app-header />
      <router-view />
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
import LoginService from './services/LoginService';

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
  async created() {
    this.loggedIn = await LoginService.checkLogin();
  },
  methods: {
    onLogin() {
      this.loggedIn = true;
    },
  },
};
</script>

<style lang="scss">
@import './app.scss';
</style>
