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

            <div class="field">
              <label class="label">DB User</label>
              <div class="select is-fullwidth">
                <select v-model="internalUser.db_user">
                  <option v-for="(dbSchema, index) in dbSchemas" :key="index">
                    {{ dbSchema.name }}
                  </option>
                </select>
              </div>
            </div>
          </div>
          <div class="column border-left">
            <label class="label">DB Schemas</label>
            <button class="button is-fullwidth is-small"
                    @click="onAddSelectedSchema(index)"
                    v-for="(selectableDbSchema, index) in selectableDbSchemas"
                    :key="index">
              <span class="flex-auto">{{ selectableDbSchema.name }}</span>
              <span class="icon is-small">
                <i class="fas fa-greater-than"></i>
              </span>
            </button>
            </div>
          <div class="column border-left">
            <label class="label">Authorized Schemas</label>
            <button class="button is-fullwidth is-small"
                    @click="onRemoveSelectedSchema(index)"
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
import CRUDService from '../services/CRUDServices';

export default {
  name: 'UserModal',
  props: {
    user: { type: Object, required: true },
  },
  async mounted() {
    this.dbSchemas = await CRUDService.dbSchemas.getAll();
    this.dbSchemas.push({ name: 'Test 1' });
    this.dbSchemas.push({ name: 'Test 2' });
    // eslint-disable-next-line
    this.selectableDbSchemas = this.dbSchemas.filter((dbSchema) => {
      // eslint-disable-next-line
      return !this.internalUser.schema_rights.some((schemaRight) => {
        return schemaRight.schema.name === dbSchema.name;
      });
    });
  },
  data() {
    return {
      // a copy of the user property to work with inside this component
      // (changing properties directly is bad practice)
      internalUser: { ...this.user },
      dbSchemas: [],
      selectableDbSchemas: [],
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
    onAddSelectedSchema(index) {
      this.internalUser.schema_rights.push({ schema: this.selectableDbSchemas[index] });
      // this.sortSchemaList(this.internalUser.schema_rights);
      this.selectableDbSchemas.splice(index, 1);
    },
    onRemoveSelectedSchema(index) {
      this.selectableDbSchemas.push(this.internalUser.schema_rights[index]);
      // this.sortSchemaList(this.selectableDbSchemas);
      this.internalUser.schema_rights.splice(index, 1);
    },
    sortSchemaList(schemas) {
      schemas.sort((a, b) => {
        const aUpper = a.name.toUpperCase();
        const bUpper = b.name.toUpperCase();
        if (aUpper < bUpper) {
          return -1;
        }
        if (aUpper > bUpper) {
          return 1;
        }
        return 0;
      });
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
