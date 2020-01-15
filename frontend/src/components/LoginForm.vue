<template>
  <div class="modal-card" style="width: auto">
      <header class="modal-card-head">
        <p class="modal-card-title">Login</p>
      </header>
      <section class="modal-card-body">
        <b-field label="Username">
          <b-input
            type="text"
            :value="userName"
            placeholder="Your username"
            required
          >
          </b-input>
        </b-field>

        <b-field label="Password">
            <b-input
                type="password"
                :value="password"
                password-reveal
                placeholder="Your password"
                required>
            </b-input>
        </b-field>
      </section>
      <footer class="modal-card-foot">
          <b-button class="button is-primary is-fullwidth" @click="submit">Login</b-button>
      </footer>
  </div>
</template>

<script>
// import LoginService from '../services/LoginService';

export default {
  data() {
    return {
      userName: null,
      password: null,
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
    async submit() {
      try {
        // await LoginService.login(this.credentials);
        console.log(this.credentials);
        this.$emit('login');
      } catch (e) {
        this.message = 'Anmeldung nicht erfolgreich!';
      }
    },
  },
};
</script>
