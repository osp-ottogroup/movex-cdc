<template>
  <div class="modal is-active">
    <div class="modal-background"
         @click="onClose"/>
    <div class="modal-card" style="width: auto">
      <header class="modal-card-head">
        <p class="modal-card-title">{{ modalTitle }}</p>
        <button class="delete"
                aria-label="close"
                @click="onClose">
        </button>
      </header>
      <section class="modal-card-body">
        <b-field label="User Name">
          <b-input v-model="internalUser.email"
                   type="text"
                   placeholder="Your e-mail address or database user"
                   required
                   validation-message="Username must not be empty">
          </b-input>
        </b-field>

        <b-field label="First Name">
          <b-input v-model="internalUser.first_name"
                   type="text"
                   placeholder="The users first name"
                   required
                   validation-message="First name must not be empty">
          </b-input>
        </b-field>

        <b-field label="Last Name">
          <b-input v-model="internalUser.last_name"
                   type="text"
                   placeholder="The users last name"
                   required
                   validation-message="Last name must not be empty">
          </b-input>
        </b-field>

        <b-field label="DB User">
          <b-input v-model="internalUser.db_user"
                   type="text"
                   placeholder="The users database user"
                   required
                   validation-message="Database user must not be empty">
          </b-input>
        </b-field>
      </section>
      <footer class="modal-card-foot">
        <button v-if="isUpdateMode"
                id="delete-button"
                class="button is-danger"
                @click="onDeleteButtonClicked">
          Delete
        </button>
        <button id="save-button"
                class="button is-primary"
                @click="onSaveButtonClicked">
          Save
        </button>
      </footer>
    </div>
  </div>
</template>

<script>
export default {
  name: 'UserModal',
  props: {
    user: { type: Object, required: true },
  },
  data() {
    return {
      // a copy of the user property to work with inside this component
      // (changing properties directly is bad practice)
      internalUser: { ...this.user },
    };
  },
  computed: {
    isUpdateMode() {
      return this.user && this.user.id;
    },
    modalTitle() {
      if (this.isUpdateMode) {
        return `Edit User (ID: ${this.user.id})`;
      }
      return 'Create User';
    },
  },
  methods: {
    onClose() {
      this.$emit('close');
    },
    onDeleteButtonClicked() {
      this.$emit('delete', this.internalUser);
    },
    onSaveButtonClicked() {
      if (this.isUpdateMode) {
        this.$emit('save', this.internalUser);
      } else {
        this.$emit('create', this.internalUser);
      }
    },
  },
};
</script>

<style lang="scss" scoped>
  #save-button {
    margin-left: auto;
  }
</style>
