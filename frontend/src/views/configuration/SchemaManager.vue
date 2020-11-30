<template>
  <div class="is-relative">
    <b-loading :active="isLoading" :is-full-page="false"/>

    <schema-table :schemas="schemas"
                  v-on="$listeners"
                  @edit-schema="onEditSchema"/>

    <template v-if="modal.show">
      <schema-modal :schema="modal.schema"
                    @saved="onSaved"
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
        show: false,
        schema: null,
      },
    };
  },
  async created() {
    await this.loadSchemas();
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
      this.modal.schema = schema;
      this.modal.show = true;
    },
    onClose() {
      this.modal.schema = null;
      this.modal.show = false;
    },
    async onSaved(savedSchema) {
      const index = this.schemas.findIndex((schema) => schema.id === savedSchema.id);
      this.$set(this.schemas, index, savedSchema);
      this.modal.schema = null;
      this.modal.show = false;
    },
  },
};
</script>
