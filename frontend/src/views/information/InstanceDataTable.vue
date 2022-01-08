<template>
  <b-table
    :data="instanceData"
    :loading="isLoading"
    striped
    hoverable>
    <b-table-column field="name" label="Name" :searchable="true" v-slot="props">
      <span class="is-block">{{ props.row.name }}</span>
      <span class="is-block has-text-grey">{{ props.row.description }}</span>
    </b-table-column>
    <b-table-column field="default_value" label="Default Value" v-slot="props">
      <span >{{ props.row.default_value }}</span>
    </b-table-column>
    <b-table-column field="startup_config_value" label="Startup Value" v-slot="props">
      <span >{{ props.row.startup_config_value }}</span>
    </b-table-column>
    <b-table-column field="value" label="Current Value" v-slot="props">
      <span >{{ props.row.value }}</span>
    </b-table-column>
  </b-table>
</template>

<script>
export default {
  name: 'InstanceDataTable',
  props: {
    instanceData: { type: Array, default: () => [] },
    isLoading: { type: Boolean, default: true },
  },
};
</script>
