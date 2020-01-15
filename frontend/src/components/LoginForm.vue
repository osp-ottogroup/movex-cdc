<template>
  <div class="modal-card" style="width: auto">
    <form @submit.prevent="onSubmit">
      <header class="modal-card-head">
        <p class="modal-card-title">Login</p>
      </header>
      <section class="modal-card-body">
        <b-field label="Username">
          <b-input
            v-model="userName"
            type="text"
            placeholder="Your username"
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
        userName: this.userName,
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
        this.toast = Toast.open({
          duration: 5000,
          message: 'Login failed',
          type: 'is-danger',
        });
      }
    },
  },
};
</script>
