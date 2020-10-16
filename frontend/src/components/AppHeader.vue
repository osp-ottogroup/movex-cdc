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
        <b-navbar-item v-if="isAdminUser" tag="router-link" :to="{ path: '/kafka-info' }">
          Kafka-Info
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
        <b-navbar-item tag="router-link" :to="{ path: '/information' }">
          <b-button icon-right="information-outline" class="circle-button"/>
        </b-navbar-item>

        <b-navbar-item tag="div" @click="showAccountInfo=!showAccountInfo" class="is-relative">
          <b-button icon-right="account" class="circle-button"/>
          <!--  TODO refactor to own component -->
          <div v-if="showAccountInfo" @click.prevent.stop>
            <div class="box" style="position: absolute; top: 100%; right: 1rem; min-width: 15rem">
              <div class="triangle"></div>
              <a class="delete" @click="showAccountInfo=false"></a>
              <div class="is-size-7">
                <p>Logged in as</p>
                <p class="is-size-6"><b>{{ user.name }}</b></p>
                <br>
                <p>Role</p>
                <p class="is-size-6">{{ roleName }}</p>
              </div>
              <br>
              <b-button type="is-primary is-light" @click="logout" expanded>
                Logout
              </b-button>
            </div>
          </div>
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
  data() {
    return {
      showAccountInfo: false,
    };
  },
  computed: {
    isAdminUser() {
      return this.user.isAdmin;
    },
    roleName() {
      return this.isAdminUser ? 'Admin' : 'User';
    },
  },
  methods: {
    logout() {
      LoginService.logout();
    },
  },
};
</script>

<style lang="scss" scoped>
.circle-button {
  border-radius: 50%;
  ::v-deep span {
    font-size: 1.3rem;
  }
}

.triangle {
  width: 0;
  height: 0;
  border-left: 5px solid transparent;
  border-right: 5px solid transparent;
  border-bottom: 10px solid white;
  position: absolute;
  top: -10px;
  right: 12px;
}

.delete {
  position: absolute;
  top: 1rem;
  right: 0.5rem;
}
</style>
