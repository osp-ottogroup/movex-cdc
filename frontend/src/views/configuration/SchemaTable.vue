<template>
  <div>
    <b-table ref="table"
             :data="schemas"
             :selected.sync="selectedSchema"
             @click="onSchemaSelected">
      <template slot-scope="props">
        <b-table-column field="name" label="Schemas">
          {{ props.row.name }}
          <b-button v-show="selectedSchema && selectedSchema.id === props.row.id"
                    icon-right="pen"
                    class="is-pulled-right is-small"
                    @click="onEditClicked()" />
        </b-table-column>
      </template>
    </b-table>

    <template v-if="showSchemaModal">
      <b-modal :active.sync="showSchemaModal"
               has-modal-card
               trap-focus
               aria-role="dialog"
               aria-modal>
        <div class="modal-card" style="width: auto">
          <header class="modal-card-head">
            <p class="modal-card-title">Edit Schema ({{modal.schema.name}})</p>
            <button class="delete"
                    aria-label="close"
                    @click="showSchemaModal = !showSchemaModal">
            </button>
          </header>
          <section class="modal-card-body">
            <b-field label="Topic">
              <b-input placeholder="Enter Topic"
                       v-model="modal.schema.topic"/>
            </b-field>
          </section>
          <footer class="modal-card-foot">
            <button id="save-schema-button"
                    class="button is-primary"
                    @click="onSaveSchema">
              Save
            </button>
          </footer>
        </div>
      </b-modal>
    </template>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'SchemaTable',
  props: {
    schemas: { type: Array, default: () => [] },
  },
  data() {
    return {
      selectedSchema: null,
      showSchemaModal: false,
      modal: {
        schema: null,
      },
    };
  },
  methods: {
    onSchemaSelected(schema) {
      this.$emit('schema-selected', schema);
    },
    onEditClicked() {
      this.modal.schema = { ...this.selectedSchema };
      this.showSchemaModal = true;
    },
    async onSaveSchema() {
      try {
        const { schema } = this.modal;
        await CRUDService.schemas.update(schema.id, { schema });
        this.$buefy.toast.open({
          message: `Saved changes to schema '${schema.name}'!`,
          type: 'is-success',
        });
        // TODO refactor components; modal should not be part of table; handling is to complex
        const done = () => {
          // select the row which was selected before schemas are reloaded
          const newSchema = this.schemas.find(s => s.id === this.selectedSchema.id);
          this.selectedSchema = newSchema;
          this.modal.schema = null;
          this.showSchemaModal = false;
        };
        this.$emit('schema-changed', done);
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
