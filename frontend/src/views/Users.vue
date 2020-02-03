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
import CRUD from '../services/CRUDServices';
import UserModal from '../components/UserModal.vue';

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
    this.users = await CRUD.users.getAll();
  },
  computed: {
    isUserSelected() {
      return this.selectedUser !== null;
    },
  },
  methods: {
    onRowClicked(user) {
      this.selectedUser = { ...user };
    },
    onCreateUserButtonClicked() {
      this.selectedUser = {};
    },
    async onSave(user) {
      await CRUD.users.update(user);
      const index = this.users.findIndex(elem => elem.id === user.id);
      this.$set(this.users, index, user);
      this.selectedUser = null;
    },
    async onDelete(user) {
      await CRUD.users.delete(user.id);
      const index = this.users.findIndex(elem => elem.id === user.id);
      this.users.splice(index, 1);
      this.selectedUser = null;
    },
    async onCreate(user) {
      const newUser = await CRUD.users.create(user);
      this.users.push(newUser);
      this.selectedUser = null;
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
