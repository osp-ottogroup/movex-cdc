<template>
  <div class="modal-card" style="width: auto">
    <form @submit.prevent="onSubmit">
      <header class="modal-card-head">
        <p class="modal-card-title">Login</p>
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
import { ToastProgrammatic as Toast } from 'buefy';
import LoginService from '../services/LoginService';
import ServerError from '../models/ServerError';

export default {
  data() {
    return {
      userName: null,
      password: null,
      toast: null,
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
        if (this.toast !== null) {
          this.toast.close();
        }
        await LoginService.login(this.credentials);
        this.$emit('login');
      } catch (e) {
        let toastMessage = 'Login failed';
        if (e instanceof ServerError) {
          toastMessage = e.data.error;
        }
        this.toast = Toast.open({
          duration: 10000,
          message: toastMessage,
          type: 'is-danger',
        });
      }
    },
  },
};
</script>
