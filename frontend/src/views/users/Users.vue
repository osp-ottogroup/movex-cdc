<template>
  <div class="columns is-centered">
    <div class="column is-half">
      <b-button
        type="is-primary"
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

    <template v-if="modal.show">
      <user-modal
        :user-id="modal.userId"
        @created="onCreated"
        @saved="onSaved"
        @deleted="onDeleted"
        @close="closeModal">
      </user-modal>
    </template>
  </div>
</template>

<script>
import CRUDService from '../../services/CRUDService';
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
      modal: {
        show: false,
        userId: null,
      },
      columns: [
        { field: 'id', label: 'ID', numeric: true },
        { field: 'first_name', label: 'First Name' },
        { field: 'last_name', label: 'Last Name' },
        { field: 'email', label: 'e-Mail' },
        { field: 'db_user', label: 'DB-User' },
      ],
    };
  },
  async created() {
    try {
      this.users = await CRUDService.users.getAll();
    } catch (e) {
      this.$buefy.notification.open({
        message: getErrorMessageAsHtml(e, 'An error occurred while loading users!'),
        type: 'is-danger',
        indefinite: true,
        position: 'is-top',
      });
    }
  },
  methods: {
    showModal(userId) {
      this.modal.userId = userId;
      this.modal.show = true;
    },
    closeModal() {
      this.modal.userId = null;
      this.modal.show = false;
    },
    onRowClicked(user) {
      this.showModal(user.id);
    },
    onCreateUserButtonClicked() {
      this.showModal(null);
    },
    onSaved(savedUser) {
      const index = this.users.findIndex(user => user.id === savedUser.id);
      this.$set(this.users, index, savedUser);
      this.closeModal();
    },
    onDeleted(deletedUser) {
      const index = this.users.findIndex(user => user.id === deletedUser.id);
      this.users.splice(index, 1);
      this.closeModal();
    },
    onCreated(createdUser) {
      this.users.push(createdUser);
      this.closeModal();
    },
  },
};
</script>

<style lang="scss" scoped>
  #users-table {
    margin-top: 1rem;
    ::v-deep tbody tr {
      cursor: pointer;
    }
  }
</style>
