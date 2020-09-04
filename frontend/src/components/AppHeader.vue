<template>
  <div id="app-header">
    <b-navbar type="is-light">

      <template v-slot:brand>
        <b-navbar-item tag="router-link" :to="{ path: '/' }">
          <span>OSP|</span>
          <strong>Trixx</strong>
        </b-navbar-item>
      </template>

      <template v-slot:start>
        <b-navbar-item tag="router-link" :to="{ path: '/' }">
            Home
        </b-navbar-item>
        <b-navbar-item v-if="isAdminUser" tag="router-link" :to="{ path: '/users' }">
            Users
        </b-navbar-item>
        <b-navbar-item tag="router-link" :to="{ path: '/configuration' }">
          Configuration
        </b-navbar-item>
        <b-navbar-item v-if="isAdminUser" tag="router-link" :to="{ path: '/deployment' }">
          Deployment
        </b-navbar-item>
        <b-navbar-dropdown v-if="isAdminUser" label="Administration">
          <b-navbar-item tag="router-link" :to="{ path: '/administration/server-log-level' }">
            Set Server Log Level
          </b-navbar-item>
          <b-navbar-item tag="router-link" :to="{ path: '/administration/server-log' }">
            Show Server Log
          </b-navbar-item>
        </b-navbar-dropdown>
      </template>

      <template v-slot:end>
        <b-navbar-item tag="div">
          <div class="is-size-7">
            logged in as:
            <b class="is-size-7">
              {{ user.name }}
            </b>
            <span v-if="isAdminUser">
              (Admin)
            </span>
          </div>
        </b-navbar-item>
        <b-navbar-item tag="div">
          <b-button @click="logout">
            Logout
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
  props: {
    user: { type: Object, default: () => {} },
  },
  computed: {
    isAdminUser() {
      return this.user.isAdmin;
    },
  },
  methods: {
    logout() {
      LoginService.logout();
    },
  },
};
</script>
