<template>
  <div class="is-relative">
    <b-loading :active="isLoading" :is-full-page="false"/>

    <table-table :tables="tables"
                 :schema="schema"
                 v-on="$listeners"
                 @edit-table="onEditTable"/>

    <b-button v-if="schema"
              id="add-table-button"
              type="is-primary"
              icon-left="plus"
              @click="onAddTable"
              expanded
              outlined>
      Add table to observe
    </b-button>

    <template v-if="modal.show">
      <table-modal :tables="selectableTables"
                   :table="modal.table"
                   :schema="schema"
                   @created="onCreated"
                   @updated="onUpdated"
                   @removed="onRemoved"
                   @close="onClose"/>
    </template>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';
import TableTable from './TableTable.vue';
import TableModal from './TableModal.vue';

export default {
  name: 'TableManager',
  components: {
    TableTable,
    TableModal,
  },
  props: {
    schema: { type: Object, default: () => {} },
  },
  data() {
    return {
      // initialize array with one empty object; will be reseted in 'mounted' hook
      // this is because buefy-table would otherwise not render headers
      tables: [{}],
      dbTables: [],
      isLoading: false,
      modal: {
        show: false,
        table: null,
      },
    };
  },
  mounted() {
    this.tables = [];
  },
  computed: {
    selectableTables() {
      // filter all tables out of db tables, that are not included in trixx tables
      return this.dbTables.filter((dbTable) => !this.tables.some((table) => dbTable.name === table.name));
    },
    showTableModal() {
      return this.modal.table !== null;
    },
  },
  methods: {
    async loadTables(schema) {
      try {
        this.isLoading = true;
        this.tables = await CRUDService.tables.getAll({ schema_id: schema.id });
        this.dbTables = await CRUDService.dbTables.getAll({ schema_name: schema.name });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading tables!'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    onAddTable() {
      this.modal.table = {
        id: null,
        schema_id: this.schema.id,
        name: '',
        info: '',
        topic: '',
        kafka_key_handling: 'N',
        fixed_message_key: '',
      };
      this.modal.show = true;
    },
    onEditTable(table) {
      this.modal.table = table;
      this.modal.show = true;
    },
    onClose() {
      this.modal.table = null;
      this.modal.show = false;
    },
    async onRemoved(removedTable) {
      const index = this.tables.findIndex((table) => table.id === removedTable.id);
      this.tables.splice(index, 1);
      this.modal.table = null;
      this.modal.show = false;
    },
    async onCreated(createdTable) {
      this.tables.push(createdTable);
      this.tables = this.tables.sort((a, b) => {
        const aName = a.name.toUpperCase();
        const bName = b.name.toUpperCase();
        if (aName < bName) { return -1; }
        if (aName > bName) { return 1; }
        return 0;
      });
      this.modal.table = null;
      this.modal.show = false;
    },
    async onUpdated(updatedTable) {
      const index = this.tables.findIndex((table) => table.id === updatedTable.id);
      this.$set(this.tables, index, updatedTable);
      this.modal.table = null;
      this.modal.show = false;
    },
  },
  watch: {
    async schema(newSchema, oldSchema) {
      if (newSchema?.id !== oldSchema?.id) {
        await this.loadTables(newSchema);
      }
    },
  },
};
</script>

<style lang="scss">
  #add-table-button {
    margin-top: 1em;
  }
</style>
