<template>
  <div class="columns is-centered">
    <div class="column is-half">
      <b-button
        @click="onCreateUserButtonClicked">
        Create User
      </b-button>
      <b-table
        id="users-table"
        :data="users"
        :columns="columns"
        striped
        hoverable
        @click="onRowClicked">
      </b-table>
    </div>
    <template v-if="isUserSelected">
      <user-modal
        :user="selectedUser"
        @create="onCreate"
        @save="onSave"
        @delete="onDelete"
        @close="onClose">
      </user-modal>
    </template>
  </div>
</template>

<script>
import CRUD from '../../services/CRUDService';
import UserModal from './UserModal.vue';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'Users',
  components: {
    UserModal,
  },
  data() {
    return {
      users: [],
      selectedUser: null,
      columns: [
        { field: 'id', label: 'ID', numeric: true },
        { field: 'first_name', label: 'First Name' },
        { field: 'last_name', label: 'Last Name' },
        { field: 'email', label: 'e-Mail' },
        { field: 'db_user', label: 'DB-User' },
      ],
    };
  },
  async mounted() {
    try {
      this.users = await CRUD.users.getAll();
    } catch (e) {
      this.$buefy.notification.open({
        message: getErrorMessageAsHtml(e, 'An error occurred while loading users!'),
        type: 'is-danger',
        indefinite: true,
        position: 'is-top',
      });
    }
  },
  computed: {
    isUserSelected() {
      return this.selectedUser !== null;
    },
  },
  methods: {
    onRowClicked(user) {
      this.selectedUser = user;
    },
    onCreateUserButtonClicked() {
      this.selectedUser = {
        id: null,
        schema_rights: [],
        yn_admin: 'N',
      };
    },
    async onSave(user) {
      try {
        await CRUD.users.update(user.id, { user });
        const index = this.users.findIndex(elem => elem.id === user.id);
        this.$set(this.users, index, user);
        this.selectedUser = null;
        this.$buefy.toast.open({
          message: 'Saved changes to user!',
          type: 'is-success',
        });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      }
    },
    async onDelete(user) {
      try {
        await CRUD.users.delete(user.id);
        const index = this.users.findIndex(elem => elem.id === user.id);
        this.users.splice(index, 1);
        this.selectedUser = null;
        this.$buefy.toast.open({
          message: 'User deleted!',
          type: 'is-success',
        });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      }
    },
    async onCreate(user) {
      try {
        const newUser = await CRUD.users.create({ user });
        this.users.push(newUser);
        this.selectedUser = null;
        this.$buefy.toast.open({
          message: 'User Created!',
          type: 'is-success',
        });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      }
    },
    onClose() {
      this.selectedUser = null;
    },
  },
};
</script>

<style lang="scss">
  #users-table tbody tr {
    cursor: pointer;
  }
</style>
