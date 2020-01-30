<template>
  <div class="columns is-centered">
    <div class="column is-half">
      <b-table id="users-table" :data="users" :columns="columns" striped hoverable
               @click="onRowClicked">
      </b-table>
    </div>
  </div>
</template>

<script>
import CRUD from '../services/CRUDServices';

export default {
  name: 'Users',
  data() {
    return {
      users: [],
      columns: [
        { field: 'id', label: 'ID', numeric: true },
        { field: 'first_name', label: 'First Name' },
        { field: 'last_name', label: 'Last Name' },
        { field: 'email', label: 'e-Mail' },
        { field: 'db_user', label: 'DB-User' },
      ],
    };
  },
  components: {},
  async mounted() {
    this.users = await CRUD.users.getAll();
    this.users.push(this.users[0]);
  },
  methods: {
    onRowClicked(user) {
      alert(`clicked user id=${user.id}`);
    },
  },
};
</script>

<style lang="scss">
  #users-table tbody tr {
    cursor: pointer;
  }
</style>
