<template>
  <div>
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
import SchemaTable from './SchemaTable.vue';
import SchemaModal from './SchemaModal.vue';
import CRUDService from '../../services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'SchemaManager',
  components: {
    SchemaTable,
    SchemaModal,
  },
  data() {
    return {
      schemas: [],
      modal: {
        schema: null,
      },
    };
  },
  async mounted() {
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
        this.schemas = await CRUDService.schemas.getAll();
      } catch (e) {
        this.$buefy.toast.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading schemas!'),
          type: 'is-danger',
          duration: 5000,
        });
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
        this.$buefy.toast.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          duration: 5000,
        });
      }
    },
  },
};
</script>
