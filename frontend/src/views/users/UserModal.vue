<template>
  <b-modal :active="true"
           has-modal-card
           trap-focus
           aria-role="dialog"
           aria-modal
           @close="onClose">
    <div class="modal-card">
      <header class="modal-card-head">
        <p class="modal-card-title">{{ modalTitle }}</p>
        <button class="delete"
                aria-label="close"
                @click="onClose">
        </button>
      </header>
      <section class="modal-card-body">
        <b-loading :active="isActionPending" :is-full-page="false"/>

        <div class="columns">
          <div class="column">
            <div class="is-size-6 mb-3">User Data</div>
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
                        required
                        @input="onDbUserChanged">
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
                  <b-icon icon="alert" size="is-small" type="is-warning"/>
                  The user has {{user.failed_logons}} failed logons.
                </p>
              </b-field>
            </b-field>
          </div>

          <div class="column is-8 border-left">
            <div class="is-size-6">Authorized Schemas</div>
            <div class="columns is-marginless">
              <div class="column">
                <b-field label="Schema" custom-class="is-small">
                  <b-select v-model="schemaRightToAdd.schema"
                            placeholder="Select a schema"
                            :loading="isLoading"
                            size="is-small"
                            expanded>
                    <option v-for="schema in authorizableDbSchemas" :key="schema.name" :value="schema">
                      {{ schema.name }}
                    </option>
                  </b-select>
                </b-field>
              </div>
              <div class="column">
                <b-field label="Deployment granted" custom-class="is-small">
                  <b-switch v-model="schemaRightToAdd.yn_deployment_granted"
                            true-value="Y"
                            false-value="N"
                            size="is-small"/>
                </b-field>
              </div>
              <div class="column">
                <b-field label="Info" custom-class="is-small">
                  <b-input v-model="schemaRightToAdd.info" size="is-small"></b-input>
                </b-field>
              </div>
              <div class="column is-2">
                <b-field custom-class="is-small">
                  <template #label>
                    <span class="is-invisible">invisible</span>
                  </template>
                  <b-button type="is-info is-light"
                            @click="onAddSchemaRight"
                            :disabled="this.schemaRightToAdd.schema === null"
                            size="is-small">
                    Add
                  </b-button>
                </b-field>
              </div>
            </div>

            <div class="mt-5 schema-rights-list">
              <div v-for="(schemaRight, index) in user.schema_rights" :key="index" class="columns is-marginless">
                <div class="column is-size-7">
                  {{ schemaRight.schema.name }}
                </div>
                <div class="column">
                  <b-switch v-model="schemaRight.yn_deployment_granted"
                            true-value="Y"
                            false-value="N"
                            size="is-small"/>
                </div>
                <div class="column">
                  <b-tooltip :label="schemaRight.info">
                    <b-input v-model="schemaRight.info" size="is-small"></b-input>
                  </b-tooltip>
                </div>
                <div class="column is-2">
                  <b-button type="is-info is-light"
                            @click="onRemoveSchemaRight(index)"
                            size="is-small">
                    Remove
                  </b-button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>
      <footer class="modal-card-foot">
        <b-button v-if="isUpdateMode"
                  id="delete-button"
                  type="is-danger"
                  @click="onDeleteButtonClicked">
          Delete
        </b-button>
        <b-button id="save-button"
                  type="is-primary"
                  @click="onSaveButtonClicked">
          {{ buttonLabel }}
        </b-button>
      </footer>
    </div>
  </b-modal>
</template>

<script>
import { getErrorMessageAsHtml } from '@/helpers';
import CRUDService from '../../services/CRUDService';

export default {
  name: 'UserModal',
  props: {
    userId: { type: Number, default: null },
  },
  async created() {
    try {
      if (this.isUpdateMode) {
        this.user = await CRUDService.users.get(this.userId);
        this.user.schema_rights.sort((a, b) => (
          a.schema.name.localeCompare(b.schema.name, undefined, { numeric: true, sensitivity: 'base' })
        ));

        this.authorizableDbSchemas = await CRUDService.dbSchemas.authorizableSchemas({ email: this.user.email, db_user: this.user.db_user });
        this.authorizableDbSchemas.sort((a, b) => (
          a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: 'base' })
        ));
      }
      this.dbSchemas = await CRUDService.dbSchemas.getAll();
    } catch (e) {
      this.$buefy.notification.open({
        message: getErrorMessageAsHtml(e, 'An error occurred while loading schemas!'),
        type: 'is-danger',
        indefinite: true,
        position: 'is-top',
      });
    } finally {
      this.isLoading = false;
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
      schemaRightToAdd: this.initialSchemaRight(),
      isLoading: true,
      isSaving: false,
      isDeleting: false,
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
    isActionPending() {
      return this.isLoading || this.isSaving || this.isDeleting;
    },
  },
  methods: {
    onClose() {
      this.$emit('close');
    },
    async onDeleteButtonClicked() {
      try {
        this.isDeleting = true;
        await CRUDService.users.delete(this.user.id, this.user);
        this.$emit('deleted', this.user);
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isDeleting = false;
      }
    },
    async onSaveButtonClicked() {
      const invalidElements = this.$el.querySelectorAll(':invalid');
      if (invalidElements.length > 0) {
        invalidElements.forEach((e) => e.reportValidity());
        return;
      }

      try {
        this.isSaving = true;
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
      } finally {
        this.isSaving = false;
      }
    },
    onAddSchemaRight() {
      this.user.schema_rights.push(this.schemaRightToAdd);
      this.user.schema_rights.sort((a, b) => (
        a.schema.name.localeCompare(b.schema.name, undefined, { numeric: true, sensitivity: 'base' })
      ));
      const index = this.authorizableDbSchemas.findIndex((s) => s.name === this.schemaRightToAdd.schema.name);
      if (index >= 0) {
        this.authorizableDbSchemas.splice(index, 1);
      }
      this.schemaRightToAdd = this.initialSchemaRight();
    },
    onRemoveSchemaRight(index) {
      this.authorizableDbSchemas.push(this.user.schema_rights[index].schema);
      this.authorizableDbSchemas.sort((a, b) => (
        a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: 'base' })
      ));
      this.user.schema_rights.splice(index, 1);
    },
    async onDbUserChanged(dbUser) {
      try {
        this.isLoading = true;
        this.authorizableDbSchemas = await CRUDService.dbSchemas.authorizableSchemas({ email: this.user.email, db_user: dbUser });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    initialSchemaRight() {
      return {
        info: '',
        yn_deployment_granted: 'N',
        schema: null,
      };
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
  .schema-rights-list {
    overflow-y: auto;
    max-height: 50vh;
    & .columns {
      border-top: 1px solid lightgray;
      &:last-of-type {
        border-bottom: 1px solid lightgray;
      }
      &:nth-of-type(even) {
        background-color: #fafafa;
      }
    }
  }
</style>
