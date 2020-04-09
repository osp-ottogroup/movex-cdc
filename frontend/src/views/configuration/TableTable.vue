<template>
  <div>
    <b-table ref="table"
             :data="tables"
             :columns="columns"
             detailed
             detail-key="id"
             :selected="currentTable"
             :show-detail-icon="false"
             @click="setCurrentTable">
      <template slot="detail" slot-scope="props">
        <b-field label="Topic" label-position="on-border">
          <b-input placeholder="Enter Topic"
                   v-model="props.row.topic"
                   size="is-small"
                   :icon-right="props.row.topicChanged ? 'save' : ''"
                   :icon-right-clickable="props.row.topicChanged"
                   @icon-right-click="onSaveTable(props.row)"
                   @input="onTopicChanged(props.row)">
          </b-input>
        </b-field>
      </template>
    </b-table>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';

export default {
  name: 'TableTable',
  props: {
    tables: { type: Array, default: () => [] },
  },
  data() {
    return {
      currentTable: null,
      columns: [
        { field: 'name', label: 'Tables' },
      ],
    };
  },
  methods: {
    setCurrentTable(table) {
      if (this.currentTable !== null) {
        this.$refs.table.toggleDetails(this.currentTable);
      }
      this.currentTable = table;
      this.$refs.table.toggleDetails(table);
      this.$emit('table-selected', table);
    },
    async onSaveTable(table) {
      try {
        await CRUDService.tables.update(table.id, { table });
        // eslint-disable-next-line no-param-reassign
        table.topicChanged = false;
        this.$buefy.toast.open({
          message: `Saved changes to table '${table.name}'!`,
          type: 'is-success',
        });
      } catch (e) {
        this.$buefy.toast.open({
          message: 'An error occurred!',
          type: 'is-danger',
          duration: 5000,
        });
      }
    },
    onTopicChanged(table) {
      if (!table.topicChanged) {
        this.$set(table, 'topicChanged', true);
      }
    },
  },
};
</script>
