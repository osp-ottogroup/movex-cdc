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

            <b-field label="e-Mail">
              <b-input v-model="internalUser.email"
                       type="text"
                       placeholder="The users e-mail address"
                       required
                       validation-message="e-Mail must not be empty">
              </b-input>
            </b-field>

            <b-field label="DB User">
              <b-select v-model="internalUser.db_user"
                        placeholder="Select a schema"
                        expanded
                        required>
                <option v-for="(dbSchema, index) in dbSchemas" :key="index">
                  {{ dbSchema.name }}
                </option>
              </b-select>
            </b-field>

            <b-field label="Admin User">
              <b-switch v-model="internalUser.yn_admin"
                        true-value="Y"
                        false-value="N"/>
            </b-field>

            <b-field label="Account Locked">
              <b-field>
                <b-switch v-model="internalUser.yn_account_locked"
                          true-value="Y"
                          false-value="N"
                          type="is-danger"/>
                <p v-if="internalUser.failed_logons > 0" class="control">
                  <b-icon icon="exclamation-triangle" size="is-small" type="is-warning"/>
                  The user has {{internalUser.failed_logons}} failed logons.
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
                    v-for="(schemaRight, index) in internalUser.schema_rights"
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
          Save
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
    user: { type: Object, required: true },
  },
  async mounted() {
    try {
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
      // a copy of the user property to work with inside this component
      // (because of changing properties directly is bad practice)
      // need JSON here, because of destructuring ( {...this.user} ) will do only a shallow copy
      // user -> schema_rights -> schema, schema would be a reference
      internalUser: JSON.parse(JSON.stringify(this.user)),
      dbSchemas: [],
      authorizableDbSchemas: [],
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
    onAddSchemaRight(index) {
      this.internalUser.schema_rights.push({
        info: 'TODO',
        schema: this.authorizableDbSchemas[index],
      });
      this.internalUser.schema_rights.sort((a, b) => (
        a.schema.name.toUpperCase() > b.schema.name.toUpperCase() ? 1 : -1
      ));
      this.authorizableDbSchemas.splice(index, 1);
    },
    onRemoveSchemaRight(index) {
      this.authorizableDbSchemas.push(this.internalUser.schema_rights[index].schema);
      this.authorizableDbSchemas.sort((a, b) => (
        a.name.toUpperCase() > b.name.toUpperCase() ? 1 : -1
      ));
      this.internalUser.schema_rights.splice(index, 1);
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
