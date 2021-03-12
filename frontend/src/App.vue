<template>
  <div id="app">
    <template v-if="isLoginCheckPending">
      <b-loading :active="isLoginCheckPending" animation="none" />
    </template>
    <template v-else>
      <template v-if="loggedIn">
        <app-header class="header"/>
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
    </template>
  </div>
</template>

<script>
import HttpService from '@/services/HttpService';
import Config from '@/config/config';
import { getErrorMessageAsHtml } from '@/helpers';
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
      isLoginCheckPending: true,
    };
  },
  async created() {
    await this.onCreated();
  },
  methods: {
    onLogin() {
      this.loggedIn = true;
    },
    async onCreated() {
      this.loggedIn = LoginService.loginWithExistingToken();
      if (this.loggedIn) {
        try {
          await HttpService.get(`${Config.backendUrl}/login/check_jwt`);
        } catch (e) {
          this.$buefy.notification.open({
            message: getErrorMessageAsHtml(e, 'An error occurred while checking the user session'),
            type: 'is-danger',
            indefinite: true,
            position: 'is-top',
          });
        }
      }
      this.isLoginCheckPending = false;
    },
  },
};
</script>

<style lang="scss">
@import './app.scss';

.header {
  margin-bottom: 1rem;
}
</style>
