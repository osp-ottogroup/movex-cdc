<template>
  <div id="app-header">
    <b-navbar type="is-light">

      <template v-slot:brand>
        <b-navbar-item tag="router-link" :to="{ path: '/' }">
          <div class="is-size-4">
            <OSPBranding></OSPBranding>
          </div>
        </b-navbar-item>
      </template>

      <template v-slot:start>
        <b-navbar-item tag="router-link" :to="{ path: '/' }" :active="$route.path === '/'">
            Home
        </b-navbar-item>
        <b-navbar-item tag="router-link" :to="{ path: '/users' }" :active="$route.path === '/users'" v-if="isAdminUser" >
            Users
        </b-navbar-item>
        <b-navbar-item tag="router-link" :to="{ path: '/configuration' }" :active="$route.path === '/configuration'">
          Configuration
        </b-navbar-item>
        <b-navbar-item tag="router-link" :to="{ path: '/deployment' }" :active="$route.path === '/deployment'" v-if="canDeploy">
          Deployment
        </b-navbar-item>
        <b-navbar-item tag="router-link" :to="{ path: '/information' }" :active="$route.path === '/information'" v-if="isAdminUser">
          Info
        </b-navbar-item>
        <b-navbar-dropdown v-if="isAdminUser"
                           label="Administration"
                           :class="{'router-link-exact-active': $route.path.startsWith('/administration/')}">
          <b-navbar-item tag="router-link"
                         :to="{ path: '/administration/server-log-level' }"
                         :active="$route.path === '/administration/server-log-level'">
            Set server log level (LOG_LEVEL)
          </b-navbar-item>
          <b-navbar-item tag="router-link"
                         :to="{ path: '/administration/worker-count' }"
                         :active="$route.path === '/administration/worker-count'">
            Set worker count (INITIAL_WORKER_THREADS)
          </b-navbar-item>
          <b-navbar-item tag="router-link"
                         :to="{ path: '/administration/max-transaction-size' }"
                         :active="$route.path === '/administration/max-transaction-size'">
            Set max. transaction size (MAX_TRANSACTION_SIZE)
          </b-navbar-item>
          <b-navbar-item tag="router-link"
                         :to="{ path: '/administration/server-log' }"
                         :active="$route.path === '/administration/server-log'">
            Show Server Log
          </b-navbar-item>
        </b-navbar-dropdown>
      </template>

      <template v-slot:end>
        <b-navbar-dropdown label="Help">
          <b-navbar-item tag="a" :href="`${backendUrl}/movex-cdc.html`" target="_blank" rel="noreferrer noopener">
            Documentation (html)
          </b-navbar-item>
          <b-navbar-item tag="a" :href="`${backendUrl}/movex-cdc.pdf`" target="_blank" rel="noreferrer noopener">
            Documentation (pdf)
          </b-navbar-item>
        </b-navbar-dropdown>
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
import Config from '@/config/config';
import UserService from '@/services/UserService';
import LoginService from '../services/LoginService';
import OSPBranding from './OspBranding.vue';

export default {
  name: 'AppHeader',
  components: {
    OSPBranding,
  },
  data() {
    return {
      showAccountInfo: false,
      backendUrl: Config.backendUrl,
      user: UserService.getUser(),
    };
  },
  computed: {
    isAdminUser() {
      return this.user.isAdmin;
    },
    canDeploy() {
      return this.user.canDeploy;
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
  border-left: 10px solid transparent;
  border-right: 10px solid transparent;
  border-bottom: 10px solid white;
  position: absolute;
  top: -8px;
  right: 7px;
}

.delete {
  position: absolute;
  top: 1rem;
  right: 0.5rem;
}

.navbar-start .router-link-exact-active {
  font-weight: 500;
}
.navbar-start .navbar-dropdown a:not(.router-link-exact-active) {
  font-weight: initial;
}
</style>
