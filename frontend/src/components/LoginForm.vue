<template>
  <div class="modal-card" style="width: auto">
    <b-loading :active="isLoading" :is-full-page="false"></b-loading>
    <form @submit.prevent="onSubmit">
      <header class="modal-card-head">
        <div class="modal-card-title is-flex is-justify-content-space-between">
          <OSPBranding></OSPBranding>
        </div>
      </header>
      <section class="modal-card-body">
        <b-field label="User Name">
          <b-input
            v-model="userName"
            type="text"
            placeholder="Your e-mail address or database user"
            required
            validation-message="Username must not be empty">
          </b-input>
        </b-field>

        <b-field label="Password">
          <b-input
            v-model="password"
            type="password"
            password-reveal
            placeholder="Your password"
            required
            validation-message="Password must not be empty">>
          </b-input>
        </b-field>

        <b-message v-if="errorMessage" type="is-danger">
          <span v-html="errorMessage"></span>
        </b-message>
      </section>
      <footer class="modal-card-foot">
        <b-button native-type="submit" class="button is-primary is-fullwidth">
          Login
        </b-button>
      </footer>
    </form>
  </div>
</template>

<script>
import { getErrorMessageAsHtml } from '@/helpers';
import OSPBranding from '@/components/OspBranding.vue';
import LoginService from '../services/LoginService';

export default {
  components: {
    OSPBranding,
  },
  data() {
    return {
      userName: null,
      password: null,
      isLoading: false,
      errorMessage: null,
    };
  },
  computed: {
    credentials() {
      return {
        email: this.userName,
        password: this.password,
      };
    },
  },
  methods: {
    async onSubmit() {
      try {
        this.isLoading = true;
        this.errorMessage = null;
        await LoginService.login(this.credentials);
        this.$emit('login');
      } catch (e) {
        this.errorMessage = getErrorMessageAsHtml(e, 'Login failed');
      } finally {
        this.isLoading = false;
      }
    },
  },
};
</script>
