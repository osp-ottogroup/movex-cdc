<template>
  <div class="modal is-active">
    <div class="modal-background"
         @click="onClose"/>
    <div class="modal-card">
      <header class="modal-card-head">
        <p class="modal-card-title">{{ modalTitle }}</p>
        <button class="delete"
                aria-label="close"
                @click="onClose">
        </button>
      </header>
      <section class="modal-card-body">
        <div class="columns">
          <div class="column">
            <b-field label="First Name">
              <b-input v-model="user.first_name"
                       type="text"
                       placeholder="The users first name"
                       required
                       validation-message="First name must not be empty">
              </b-input>
            </b-field>

            <b-field label="Last Name">
              <b-input v-model="user.last_name"
                       type="text"
                       placeholder="The users last name"
                       required
                       validation-message="Last name must not be empty">
              </b-input>
            </b-field>

            <b-field label="e-Mail">
              <b-input v-model="user.email"
                       type="text"
                       placeholder="The users e-mail address"
                       required
                       validation-message="e-Mail must not be empty">
              </b-input>
            </b-field>

            <b-field label="DB User">
              <b-select v-model="user.db_user"
                        placeholder="Select a schema"
                        expanded
                        required>
                <option v-for="(dbSchema, index) in dbSchemas" :key="index">
                  {{ dbSchema.name }}
                </option>
              </b-select>
            </b-field>

            <b-field label="Admin User">
              <b-switch v-model="user.yn_admin"
                        true-value="Y"
                        false-value="N"/>
            </b-field>

            <b-field label="Account Locked">
              <b-field>
                <b-switch v-model="user.yn_account_locked"
                          true-value="Y"
                          false-value="N"
                          type="is-danger"/>
                <p v-if="user.failed_logons > 0" class="control">
                  <b-icon icon="exclamation-triangle" size="is-small" type="is-warning"/>
                  The user has {{user.failed_logons}} failed logons.
                </p>
              </b-field>
            </b-field>

          </div>

          <div class="column border-left">
            <label class="label">DB Schemas</label>
            <button class="button is-fullwidth is-small"
                    @click="onAddSchemaRight(index)"
                    v-for="(authorizableDbSchema, index) in authorizableDbSchemas"
                    :key="index">
              <span class="flex-auto">{{ authorizableDbSchema.name }}</span>
              <span class="icon is-small">
                <i class="fas fa-greater-than"></i>
              </span>
            </button>
          </div>

          <div class="column border-left">
            <label class="label">Authorized Schemas</label>
            <button class="button is-fullwidth is-small"
                    @click="onRemoveSchemaRight(index)"
                    v-for="(schemaRight, index) in user.schema_rights"
                    :key="index">
              <span class="icon is-small">
                <i class="fas fa-less-than"></i>
              </span>
              <span class="flex-auto">{{ schemaRight.schema.name }}</span>
            </button>
          </div>
        </div>
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
          {{ buttonLabel }}
        </button>
      </footer>
    </div>
  </div>
</template>

<script>
import CRUDService from '../../services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'UserModal',
  props: {
    userId: { type: Number, default: null },
  },
  async created() {
    try {
      if (this.isUpdateMode) {
        this.user = await CRUDService.users.get(this.userId);
      }
      this.dbSchemas = await CRUDService.dbSchemas.getAll();
      this.authorizableDbSchemas = await CRUDService.dbSchemas.authorizableSchemas({ email: this.user.email });
    } catch (e) {
      this.$buefy.notification.open({
        message: getErrorMessageAsHtml(e, 'An error occurred while loading schemas!'),
        type: 'is-danger',
        indefinite: true,
        position: 'is-top',
      });
    }
  },
  data() {
    return {
      user: {
        id: null,
        email: null,
        db_user: null,
        first_name: null,
        last_name: null,
        yn_admin: 'N',
        yn_account_locked: 'N',
        schema_rights: [],
      },
      dbSchemas: [],
      authorizableDbSchemas: [],
    };
  },
  computed: {
    isUpdateMode() {
      return this.userId !== null;
    },
    modalTitle() {
      if (this.isUpdateMode) {
        return `Edit User (ID: ${this.userId})`;
      }
      return 'Create User';
    },
    buttonLabel() {
      if (this.isUpdateMode) {
        return 'Save';
      }
      return 'Create';
    },
  },
  methods: {
    onClose() {
      this.$emit('close');
    },
    async onDeleteButtonClicked() {
      try {
        await CRUDService.users.delete(this.user.id);
        this.$emit('deleted', this.user);
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      }
    },
    async onSaveButtonClicked() {
      const invalidElements = this.$el.querySelectorAll(':invalid');
      if (invalidElements.length > 0) {
        invalidElements.forEach(e => e.reportValidity());
        return;
      }

      try {
        if (this.isUpdateMode) {
          await CRUDService.users.update(this.user.id, { user: this.user });
          this.$emit('saved', this.user);
        } else {
          const newUser = await CRUDService.users.create({ user: this.user });
          this.$emit('created', newUser);
        }
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      }
    },
    onAddSchemaRight(index) {
      this.user.schema_rights.push({
        info: 'TODO',
        schema: this.authorizableDbSchemas[index],
      });
      this.user.schema_rights.sort((a, b) => (
        a.schema.name.toUpperCase() > b.schema.name.toUpperCase() ? 1 : -1
      ));
      this.authorizableDbSchemas.splice(index, 1);
    },
    onRemoveSchemaRight(index) {
      this.authorizableDbSchemas.push(this.user.schema_rights[index].schema);
      this.authorizableDbSchemas.sort((a, b) => (
        a.name.toUpperCase() > b.name.toUpperCase() ? 1 : -1
      ));
      this.user.schema_rights.splice(index, 1);
    },
  },
};
</script>

<style lang="scss" scoped>
  #save-button {
    margin-left: auto;
  }
  .modal-card {
    width: 1024px;
  }
  .border-left {
    border-left: 1px solid lightgray;
  }
  .flex-auto {
    flex: auto;
  }
</style>
