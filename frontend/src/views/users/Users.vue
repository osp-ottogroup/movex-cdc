<template>
  <div class="columns is-centered">
    <div class="column is-half">
      <div class="level">
        <div class="level-left">
          <b-button
            type="is-primary"
            @click="onCreateUserButtonClicked">
            Create User
          </b-button>
        </div>
        <div class="level-right">
          <b-button
            type="is-info"
            icon-left="magnify"
            @click="onSearchButtonClicked"/>
        </div>
      </div>

      <b-table
        id="users-table"
        :data="users"
        :loading="isLoading"
        default-sort="last_name"
        striped
        hoverable
        @click="onRowClicked">
          <b-table-column field="id" label="ID" numeric sortable :searchable="showSearchFields" v-slot="props">
            {{ props.row.id }}
          </b-table-column>
          <b-table-column field="first_name" label="First Name" sortable :searchable="showSearchFields" v-slot="props">
            {{ props.row.first_name }}
          </b-table-column>
          <b-table-column field="last_name" label="Last Name" sortable :searchable="showSearchFields" v-slot="props">
            {{ props.row.last_name }}
          </b-table-column>
          <b-table-column field="email" label="e-Mail" sortable :searchable="showSearchFields" v-slot="props">
            {{ props.row.email }}
          </b-table-column>
          <b-table-column field="db_user" label="DB-User" sortable :searchable="showSearchFields" v-slot="props">
            {{ props.row.db_user }}
          </b-table-column>
          <b-table-column label="Info" width="4rem" v-slot="props">
            <span>
              <b-tooltip label="Admin User" type="is-light">
                <b-icon v-if="props.row.yn_admin === 'Y'" icon="account-circle" size="is-small"/>
              </b-tooltip>
              <b-tooltip label="Account is locked" type="is-light">
                <b-icon v-if="props.row.yn_account_locked === 'Y'" icon="lock" size="is-small"/>
              </b-tooltip>
            </span>
          </b-table-column>
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
import { getErrorMessageAsHtml } from '@/helpers';
import CRUDService from '../../services/CRUDService';
import UserModal from './UserModal.vue';

export default {
  name: 'Users',
  components: {
    UserModal,
  },
  data() {
    return {
      isLoading: true,
      users: [],
      showSearchFields: false,
      modal: {
        show: false,
        userId: null,
      },
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
    } finally {
      this.isLoading = false;
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
    onSearchButtonClicked() {
      this.showSearchFields = !this.showSearchFields;
    },
    onSaved(savedUser) {
      const index = this.users.findIndex((user) => user.id === savedUser.id);
      this.$set(this.users, index, savedUser);
      this.closeModal();
    },
    onDeleted(deletedUser) {
      const index = this.users.findIndex((user) => user.id === deletedUser.id);
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
