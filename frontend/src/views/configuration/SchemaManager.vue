<template>
  <div class="is-relative">
    <b-loading :active="isLoading" :is-full-page="false"/>

    <schema-table :schemas="schemas"
                  v-on="$listeners"
                  @edit-schema="onEditSchema"/>
    <template v-if="showSchemaModal">
      <schema-modal :schema="modal.schema"
                    @save="onSave"
                    @close="onClose"/>
    </template>
  </div>
</template>

<script>
import { getErrorMessageAsHtml } from '@/helpers';
import SchemaTable from './SchemaTable.vue';
import SchemaModal from './SchemaModal.vue';
import CRUDService from '../../services/CRUDService';

export default {
  name: 'SchemaManager',
  components: {
    SchemaTable,
    SchemaModal,
  },
  data() {
    return {
      schemas: [],
      isLoading: true,
      modal: {
        schema: null,
      },
    };
  },
  async created() {
    await this.loadSchemas();
  },
  computed: {
    showSchemaModal() {
      return this.modal.schema !== null;
    },
  },
  methods: {
    async loadSchemas() {
      try {
        this.isLoading = true;
        const schemas = await CRUDService.schemas.getAll();
        this.schemas = schemas.sort((a, b) => {
          const aName = a.name.toUpperCase();
          const bName = b.name.toUpperCase();
          if (aName < bName) { return -1; }
          if (aName > bName) { return 1; }
          return 0;
        });
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
    onEditSchema(schema) {
      this.modal.schema = { ...schema };
    },
    onClose() {
      this.modal.schema = null;
    },
    async onSave(changedSchema) {
      try {
        const updatedSchema = await CRUDService.schemas.update(changedSchema.id, { schema: changedSchema });
        this.$buefy.toast.open({
          message: `Saved changes to schema '${updatedSchema.name}'!`,
          type: 'is-success',
        });
        // TODO needs a better way of copying properties without dereferencing original object
        this.schemas.some((schema) => {
          if (schema.id === updatedSchema.id) { /* eslint-disable no-param-reassign */
            schema.name = updatedSchema.name;
            schema.topic = updatedSchema.topic;
            schema.created_at = updatedSchema.created_at;
            schema.updated_at = updatedSchema.updated_at;
            return true;
          }
          return false;
        });
        this.modal.schema = null;
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      }
    },
  },
};
</script>
