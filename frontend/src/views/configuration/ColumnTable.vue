<template>
  <div>
    <b-table ref="table"
             :data="columns"
             striped
             hoverable>
      <template slot-scope="props">
        <b-table-column field="name" label="Columns" searchable>
          <template slot="searchable" slot-scope="props">
            <b-input v-model="props.filters[props.column.field]"
                     icon="magnify"
                     size="is-small"/>
          </template>

          {{ props.row.name }}
        </b-table-column>
        <b-table-column centered field="name" label="Insert-Trigger">
          <b-switch size="is-small"
                    true-value="Y"
                    false-value="N"
                    v-model="props.row.yn_log_insert"
                    @input="onColumnChanged(props.row)"/>
        </b-table-column>
        <b-table-column centered field="name" label="Update-Trigger">
          <b-switch size="is-small"
                    true-value="Y"
                    false-value="N"
                    v-model="props.row.yn_log_update"
                    @input="onColumnChanged(props.row)"/>
        </b-table-column>
        <b-table-column centered field="name" label="Delete-Trigger">
          <b-switch size="is-small"
                    true-value="Y"
                    false-value="N"
                    v-model="props.row.yn_log_delete"
                    @input="onColumnChanged(props.row)"/>
        </b-table-column>
      </template>
    </b-table>
  </div>
</template>

<script>
export default {
  name: 'ColumnTable',
  props: {
    columns: { type: Array, default: () => [] },
  },
  methods: {
    onColumnChanged(column) {
      this.$emit('column-changed', column);
    },
  },
};
</script>
