<template>
  <div id="app-header">
    <b-navbar type="is-light">

      <template slot="brand">
        <b-navbar-item tag="router-link" :to="{ path: '/' }">
          OSP| Trixx
        </b-navbar-item>
      </template>

      <template slot="start">
        <b-navbar-item tag="router-link" :to="{ path: '/' }">
            Home
        </b-navbar-item>
        <b-navbar-item tag="router-link" :to="{ path: '/users' }">
            Users
        </b-navbar-item>
      </template>

      <template slot="end">
        <b-navbar-item tag="div">
          <div class="is-size-7">
            logged in as:
            <b class="is-size-7">
              {{ userName }}
            </b>
          </div>
        </b-navbar-item>
        <b-navbar-item tag="div">
          <b-button @click="logout">
            Abmelden
          </b-button>
        </b-navbar-item>
      </template>

    </b-navbar>
  </div>
</template>

<script>
import LoginService from '../services/LoginService';

export default {
  name: 'AppHeader',
  data: () => ({ userName: 'Sandro Admin' }),
  methods: {
    logout() {
      LoginService.logout();
    },
  },
};
</script>
